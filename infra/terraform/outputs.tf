# === Sensitive outputs (for .env / wrangler secret) ===

output "service_token_client_id" {
  description = "Service Token client_id for MCP clients (CF_ACCESS_CLIENT_ID)"
  value       = cloudflare_zero_trust_access_service_token.mcp.client_id
  sensitive   = true
}

output "service_token_client_secret" {
  description = "Service Token client_secret for MCP clients (CF_ACCESS_CLIENT_SECRET)"
  value       = cloudflare_zero_trust_access_service_token.mcp.client_secret
  sensitive   = true
}

# === Non-sensitive outputs (for wrangler.toml / docs) ===

output "ai_search_instance_uuid" {
  description = "AI Search instance public_endpoint_id (UUID) for Worker AI_SEARCH_INSTANCE var (used in public endpoint URL)"
  value       = cloudflare_ai_search_instance.poc.public_endpoint_id
}

output "ai_search_instance_name" {
  description = "AI Search instance name for REST API path"
  value       = cloudflare_ai_search_instance.poc.id
}

output "r2_bucket_name" {
  description = "R2 bucket name for corpus uploads"
  value       = cloudflare_r2_bucket.corpus.name
}

output "ai_gateway_id" {
  description = "AI Gateway ID"
  value       = cloudflare_ai_gateway.gw.id
}

output "worker_url" {
  description = "Worker public URL (Access endpoints の base、cutover verify で参照)"
  value       = "https://${local.worker_url}"
}

# NOTE: AI_SEARCH_API_TOKEN (Worker secret) は同じ var.cloudflare_api_token を使う想定。
# Justfile sync-secrets recipe では .env からそのまま wrangler secret put に流す。
# Phase 2 で scope を絞った専用 cloudflare_api_token resource に切替予定。
