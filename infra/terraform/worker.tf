# Worker script 本体は wrangler 主導 (本 ADR §Decision)。
# Terraform は workers.dev subdomain の有効化のみ管理する。
#
# NOTE: workers.dev subdomain (instance.config.yaml の `infra.workers_dev_subdomain`)
# はアカウント単位の設定で、script 名 = local.names.worker_script に紐付ける。
# script 本体が wrangler でまだ deploy されていない状態で apply すると
# 「script not found」エラーになる → cutover 手順では先に wrangler deploy
# を済ませてから terraform apply する。
resource "cloudflare_workers_script_subdomain" "main" {
  account_id       = local.config.infra.cloudflare_account_id
  script_name      = local.names.worker_script
  enabled          = true
  previews_enabled = false
}
