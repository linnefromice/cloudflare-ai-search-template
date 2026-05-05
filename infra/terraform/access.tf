# Cloudflare Access OTP IdP.
# Phase 1 IdP: One-time PIN with email allowlist (configured via instance.config.yaml `otp_email_domain`).
# 本格運用時は type を "google-apps" 等に切替予定。
#
# config は schema 上 required (nested object)。type = "onetimepin" の場合
# OAuth/SAML 系フィールドは不要なので空オブジェクトで渡す。
resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  account_id = local.config.infra.cloudflare_account_id
  name       = local.names.otp_idp
  type       = "onetimepin"

  config = {}
}

# Service Token for MCP endpoint (used by Claude Desktop / cloudflared CLI).
# client_secret はリソース作成時に Cloudflare 側で生成、computed attribute として state に保存。
# outputs.tf 経由で MCP クライアント側に渡す。
resource "cloudflare_zero_trust_access_service_token" "mcp" {
  account_id = local.config.infra.cloudflare_account_id
  name       = local.names.service_token
  duration   = "8760h" # 1 year
}

# ============================================================
# Policies (standalone resources, referenced from applications via policies = [{id = ...}])
# ============================================================

# Policy 1: allow the configured email domain via OTP (used by catchall app)
resource "cloudflare_zero_trust_access_policy" "chat_otp" {
  account_id = local.config.infra.cloudflare_account_id
  name       = "OTP @${local.config.infra.otp_email_domain}"
  decision   = "allow"

  include = [
    {
      email_domain = {
        domain = local.config.infra.otp_email_domain
      }
    }
  ]
}

# Policy 2: allow only the configured Service Token (used by mcp app)
resource "cloudflare_zero_trust_access_policy" "mcp_service_token" {
  account_id = local.config.infra.cloudflare_account_id
  name       = "Service Token: ${local.names.service_token}"
  decision   = "non_identity"

  include = [
    {
      service_token = {
        token_id = cloudflare_zero_trust_access_service_token.mcp.id
      }
    }
  ]
}

# ============================================================
# Applications (2 self-hosted apps on workers.dev URL)
#
# 設計判断: 本テンプレートでは catchall app (whole domain except /mcp) を OTP IdP で
# 保護し、/mcp は Service Token 専用 app として別 policy で扱う。
#
# 注: Cloudflare Access の cookie scope は per-app のため、UI で /chat/completions 等を
# fetch すると path-specific app の cookie が無く CORS error で fail する。これを
# 避けるため /chat/completions など chat UI が叩く path は catchall に統合し、
# Service Token 専用の /mcp だけ別 app として分離している。
# ============================================================

# Access app: /mcp endpoint (Service Token only, non-interactive)
resource "cloudflare_zero_trust_access_application" "mcp" {
  account_id           = local.config.infra.cloudflare_account_id
  name                 = local.names.access_app_mcp
  type                 = "self_hosted"
  session_duration     = "8h"
  app_launcher_visible = false
  allowed_idps         = [] # Service Token only — no IdP needed

  destinations = [{
    type = "public"
    uri  = "${local.worker_url}/mcp"
  }]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.mcp_service_token.id
    precedence = 1
  }]
}

# Access app: catchall (whole domain except /mcp which has higher-precedence app)
# Policy: OTP @<otp_email_domain> (any user with that email domain).
resource "cloudflare_zero_trust_access_application" "catchall" {
  account_id                = local.config.infra.cloudflare_account_id
  name                      = local.names.access_app_catchall
  type                      = "self_hosted"
  session_duration          = "8h"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.otp.id]
  auto_redirect_to_identity = true
  app_launcher_visible      = false

  destinations = [{
    type = "public"
    uri  = local.worker_url
  }]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.chat_otp.id
    precedence = 1
  }]
}
