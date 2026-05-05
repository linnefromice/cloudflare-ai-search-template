# R2 bucket for AI Search corpus.
# `location` は初回作成時のみ反映される (provider docs 注記)。
# Phase 1 は apac (Cloudflare account region に近い)。
resource "cloudflare_r2_bucket" "corpus" {
  account_id    = local.config.infra.cloudflare_account_id
  name          = local.names.r2_bucket
  location      = "apac"
  storage_class = "Standard"
}
