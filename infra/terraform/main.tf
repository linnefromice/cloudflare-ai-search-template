locals {
  # instance 固有値の単一集約 (spec ADR 0002 §3.3)。
  # この yaml が Cloudflare 管理の prefix / account_id / OTP allowlist 等の SoT。
  config = yamldecode(file("${path.module}/../../instance.config.yaml"))

  # 既存リソース名を維持 (greenfield 再構築でも同じ名前で再作成)
  prefix = local.config.infra.prefix

  # Worker public URL — Access destinations / outputs で使う single source of truth
  worker_url = "${local.prefix}.${local.config.infra.workers_dev_subdomain}.workers.dev"

  names = {
    r2_bucket           = "${local.prefix}-corpus"
    ai_search_instance  = "${local.prefix}-instance"
    ai_gateway          = "${local.prefix}-gw"
    worker_script       = local.prefix
    service_token       = "${local.prefix}-mcp"
    otp_idp             = "OTP @${local.config.infra.otp_email_domain}"
    access_app_chat     = "${local.prefix}-chat"
    access_app_mcp      = "${local.prefix}-mcp"
    access_app_catchall = "${local.prefix}-catchall"
  }
}
