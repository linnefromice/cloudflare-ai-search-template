# terraform variables — secrets only.
# Non-secret 設定 (account_id / OTP domain / operator email / workers.dev subdomain
# / prefix 等) は ../../instance.config.yaml に集約 (spec ADR 0002 §3.2 #3
# 「terraform.tfvars と instance.config.yaml の二重管理を避ける」)。

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token. Scopes: AI Search (Edit + Read + Run + Index), R2 Storage (Edit), Workers Scripts (Edit), Access (Apps and Policies + Identity Providers + Service Tokens — all Edit), AI Gateway (Edit)."
  sensitive   = true
}

variable "cloudflare_api_token_id" {
  type        = string
  description = "UUID (32-char hex) of cloudflare_api_token. Look up via /user/tokens/verify. Required by cloudflare_ai_search_token.cf_api_id (registers the token as the credential AI Search uses to read R2)."
  sensitive   = true
}
