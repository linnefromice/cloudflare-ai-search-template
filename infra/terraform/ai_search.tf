# AI Gateway: provider key (Google AI Studio 等) の保管 + 観測層。
# 多くのフィールドが Required (provider 仕様上)、現行 Dashboard default 値を明示。
resource "cloudflare_ai_gateway" "gw" {
  account_id                 = local.config.infra.cloudflare_account_id
  id                         = local.names.ai_gateway
  cache_invalidate_on_update = false
  cache_ttl                  = 0 # No caching at gateway layer (AI Search has its own cache)
  collect_logs               = true
  rate_limiting_interval     = 0 # Disabled
  rate_limiting_limit        = 0 # Disabled
  rate_limiting_technique    = "fixed"
  # Authenticated Gateway: Vault (provider keys) を使うために必須。
  # AI Search → AI Gateway は internal binding 経由なので cf-aig-authorization header は不要
  # (binding requests are pre-authenticated). 外部 client が直接叩く時のみ token が必要。
  authentication             = true
  logpush                    = false

  # store_id は Cloudflare Secrets Store の自動 bind ID。
  # Dashboard で provider key (Google AI Studio 等) を Add → 自動的に Secrets Store
  # が生成され store_id がここに紐付く。terraform 入力に含めないと apply 時に
  # null で上書きされ Vault key が失活するため、明示的に ignore_changes する。
  # 詳細: https://developers.cloudflare.com/ai-gateway/configuration/bring-your-own-keys/
  lifecycle {
    ignore_changes = [store_id]
  }
}

# AI Search が R2 bucket を読むための internal token registration。
# cf_api_id / cf_api_key には R2:Edit scope を持つ Cloudflare API token の
# id と value を渡す (= var.cloudflare_api_token を流用、scope は外部で広めに発行済)。
# import 非対応 (provider 制約) のため、greenfield 再構築前提で扱う。
resource "cloudflare_ai_search_token" "instance_token" {
  account_id = local.config.infra.cloudflare_account_id
  cf_api_id  = var.cloudflare_api_token_id  # token UUID (NOT a label) — see https://developers.cloudflare.com/ai-search/configuration/service-api-token/
  cf_api_key = var.cloudflare_api_token
  name       = "${local.prefix}-instance-token"
}

# AI Search instance.
# embedding_model は作成時固定 (Cloudflare 仕様)、後から変更不可。
#
# system_prompt_aisearch は worker/src/prompts/system-prompt.v2.1.md (rendered)
# の本文 (最初の "\n---\n" 以降) を直接渡す。
# 当該ファイルは build-prompt.ts により system-prompt.v2.1.template.md +
# instance.config.yaml から render される generated。
#
# IMPORTANT: terraform apply の前に以下を実行して generated ファイルを作成すること:
#   bun install   # scripts/ 配下、初回のみ
#   bun run scripts/build-prompt.ts --version v2.1
# ($JUSTFILE の bootstrap recipe で自動化済)
resource "cloudflare_ai_search_instance" "poc" {
  account_id    = local.config.infra.cloudflare_account_id
  id            = local.names.ai_search_instance
  ai_gateway_id = cloudflare_ai_gateway.gw.id
  token_id      = cloudflare_ai_search_token.instance_token.id
  type          = "r2"
  source        = local.names.r2_bucket  # bucket name

  # Source: external R2 bucket name (Cloudflare AI Search 2026-04-16 仕様変更後、
  # source は R2 bucket name を直接指定する)。
  # 参考: https://developers.cloudflare.com/ai-search/get-started/api/

  # Models
  embedding_model = "@cf/qwen/qwen3-embedding-0.6b"
  aisearch_model  = "google-ai-studio/gemini-2.5-flash"
  reranking       = false
  reranking_model = "@cf/baai/bge-reranker-base"

  # Retrieval / chunking
  # NOTE: chunk_overlap は 0-30 の範囲 (provider validate で確認済 2026-05-03)
  fusion_method   = "rrf"
  max_num_results = 10
  chunk_size      = 512
  chunk_overlap   = 30

  # Hybrid search 設定 (Recall@5 を高水準に保つための baseline 構成)。
  # 新 instance default は vector only で、spec-detail 系の exact-keyword 質問
  # (固有 ID / コード等) が hit せず Recall@5 が劣化する傾向のため明示。
  # NOTE: keyword_tokenizer 変更は full re-index を triggers (provider doc 警告)。
  index_method = {
    keyword = true
    vector  = true
  }
  indexing_options = {
    keyword_tokenizer = "trigram"
  }
  retrieval_options = {
    keyword_match_mode = "or"
  }

  # Behavior
  cache           = false
  cache_threshold = "close_enough"
  rewrite_query   = false
  summarization   = false
  paused          = false

  # System Prompt (provider 5.x で直接管理可能)
  system_prompt_aisearch = trimspace(
    split("\n---\n", file("${path.module}/../../worker/src/prompts/system-prompt.v2.1.md"))[1]
  )

  # Source binding (R2 bucket).
  # bucket name は source attribute 上部で指定 (2026-04-16 仕様変更後の正解)。
  # source_params は path filter のみで bucket name は渡さない。
  source_params = {
    # path filter は使わない (corpus 全体を index 対象)
  }

  # Public endpoint enable: MCP / chat snippet / public chat/completions の base。
  # Worker の AI_SEARCH_INSTANCE var が指す UUID は ここを enable した時点で発行される。
  # 内部の各 endpoint (mcp / search / chat_completions) は default で有効。
  public_endpoint_params = {
    enabled = true
    # rate_limit は API default 値を明示。null だと PUT が 7001 で fail する。
    rate_limit = {
      requests   = 120
      period_ms  = 60000
      technique  = "fixed"
    }
  }
}
