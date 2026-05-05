# cloudflare-ai-search-template

**Cloudflare AI Search** (旧 AutoRAG) を使った社内ナレッジ検索 (RAG) PoC のテンプレート。Markdown を SoT (Source of Truth) として、retrieval + generation + Access 認証 + MCP 連携を Terraform / Worker / Mustache テンプレで一気に立ち上げる構成。

## 何が立ち上がる

```
GitHub (corpus Markdown) ──wrangler r2 put──▶ Cloudflare R2
                                                  │ auto-watch
                                                  ▼
                                          Cloudflare AI Search instance
                                            ├ Vectorize (embedding: qwen3-0.6b)
                                            ├ Hybrid search (vector + keyword/trigram + RRF)
                                            └ Generation (default: Gemini 2.5 Flash via AI Gateway)
                                                  │
                            ┌─────────────────────┼─────────────────────┐
                            ▼                     ▼                     ▼
                    Public Endpoint        REST API            MCP endpoint
                            │                     │                     │
                            └────── Worker proxy ─┼─────────────────────┘
                                    │  + Snippet UI (chat-page-snippet)
                                    │  + /mcp passthrough
                                    ▼
                            Cloudflare Access × 2 apps
                              ├ catchall: OTP @your-domain.com
                              └ /mcp: Service Token (for Claude Desktop / cloudflared)
                                    │
                                    ▼
                            ブラウザ / Claude Desktop / CLI
```

リソース計 13 個を Terraform で declarative に管理。Worker 本体だけ wrangler 主導。

## 主要技術

- **インフラ**: [Cloudflare](https://www.cloudflare.com/) (Workers Paid + R2 + AI Search + AI Gateway + Zero Trust Access)
- **IaC**: [Terraform](https://www.terraform.io/) + [`cloudflare/cloudflare ~> 5`](https://registry.terraform.io/providers/cloudflare/cloudflare/) provider
- **Worker runtime**: TypeScript + [`wrangler`](https://developers.cloudflare.com/workers/wrangler/)
- **Build / scripts**: [`bun`](https://bun.sh/) + [Mustache](https://mustache.github.io/)
- **Task runner**: [`just`](https://just.systems/)
- **System Prompt**: Mustache template + `instance.config.yaml` で render

## クイックスタート

> **詳細な手順 / トラブルシュート / カスタマイズは [`docs/USAGE.md`](docs/USAGE.md) を参照**。本セクションは最短経路 (= 60 分で動かすため) のサマリ。

### 0. 前提

- Cloudflare account (Workers Paid + Zero Trust 有効化済)
- macOS / Linux + `bash`
- ツール: `terraform`, `just`, `bun`, `wrangler`

```bash
brew install hashicorp/tap/terraform just
curl -fsSL https://bun.sh/install | bash
npm install -g wrangler
```

### 1. clone + 初期設定

```bash
git clone https://github.com/linnefromice/cloudflare-ai-search-template.git
cd cloudflare-ai-search-template

# instance 固有値を編集
cp instance.config.example.yaml instance.config.yaml
$EDITOR instance.config.yaml
# ↓ 必須項目:
#   infra.prefix                  : 全 resource の prefix (例: my-aisearch-poc)
#   infra.cloudflare_account_id   : Dashboard 右上 or `wrangler whoami` で取得
#   infra.workers_dev_subdomain   : *.workers.dev のサブドメイン
#   infra.otp_email_domain        : OTP IdP 許可ドメイン
#   infra.operator_email          : Access catchall app の許可 user
#   org.name / org.short_name     : 組織名 (System Prompt と UI に注入)
#   domains[]                     : 検索対象ドメインの分類軸 (corpus と整合)
```

### 2. corpus 配置

`corpus/<domain>/<repo>/<original-path>.md` の path-based 命名で markdown を配置。frontmatter スキーマは `corpus/README.md` 参照。

```bash
# 例
mkdir -p corpus/product/my-app/docs
$EDITOR corpus/product/my-app/docs/architecture.md
```

### 3. Cloudflare API Token 発行

Dashboard → My Profile → API Tokens → Create Token → custom token で以下 scope:

- AI Search: Edit
- R2: Edit
- Workers Scripts: Edit
- Access (Apps and Policies + IdP/Groups + Service Tokens): Edit
- AI Gateway: Edit

```bash
cd infra/terraform
cp .env.example .env
$EDITOR .env
# TF_VAR_cloudflare_api_token   : 上記 token
# TF_VAR_cloudflare_api_token_id: 以下で取得
#   curl -s -H "Authorization: Bearer $TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify | jq -r '.result.id'
```

### 4. Bootstrap

```bash
# まず Worker を deploy (terraform の workers_script_subdomain が script を参照する前段)
cd ../../worker
cp wrangler.toml.example wrangler.toml
$EDITOR wrangler.toml   # name / account_id を instance.config.yaml と揃える
wrangler deploy

# Terraform で 13 リソースを作成 (build-prompt → init → plan → apply の chain)
cd ../infra/terraform
just bootstrap

# Service Token / instance UUID を Worker secret + root .env に sync
just sync-secrets

# Worker を再 deploy (instance UUID が wrangler.toml に入った状態で)
cd ../../worker
wrangler deploy
```

### 5. AI Gateway Vault に provider key を投入

Cloudflare Dashboard → AI → AI Gateway → `<prefix>-gw` → Settings → Vault → Add Provider Key で Google AI Studio (default の Gemini 2.5 Flash 利用時) の API key を登録。

> 別 provider (OpenAI / Anthropic 等) を使いたい場合: `infra/terraform/ai_search.tf` の `aisearch_model` を変更後、Vault に対応 provider key を投入。

### 6. corpus を R2 に sync

```bash
cd corpus
export CLOUDFLARE_ACCOUNT_ID=<your-account-id>
PREFIX=$(grep -E '^\s*prefix:' ../instance.config.yaml | awk '{print $2}')
for f in $(find . -type f -name '*.md' ! -name 'README.md'); do
  wrangler r2 object put "${PREFIX}-corpus/${f#./}" --file="$f" --remote
done
```

数秒〜数十秒で AI Search が auto-watch で再 index する。Dashboard → AI → AI Search → `<prefix>-instance` → Indexed: N/N で確認。

### 7. 動作確認

```bash
# Worker URL を terraform output から取得
cd infra/terraform
WORKER_URL=$(terraform output -raw worker_url)

# OTP 認証込みのブラウザアクセス
open $WORKER_URL
# → Cloudflare Access の OTP プロンプト → メール届く → コード入力 → chat UI が出る
```

## 構成

```
.
├── instance.config.example.yaml   # instance 固有値のテンプレ (cp して編集)
├── corpus/                        # path-based markdown corpus (R2 sync 対象)
│   └── README.md                  # 命名規約 + frontmatter スキーマ
├── worker/
│   ├── wrangler.toml.example      # Worker 設定テンプレ (cp して編集)
│   └── src/
│       ├── index.ts               # AI Search への薄い proxy + chat UI
│       └── prompts/
│           ├── system-prompt.v2.1.template.md  # Mustache template (current)
│           ├── system-prompt.v2.template.md    # 旧 version (reference)
│           └── CHANGELOG.md
├── scripts/
│   ├── build-prompt.ts            # Mustache renderer (template + config → SP)
│   ├── lint-domain-enum.ts        # config と corpus README の domain 同期 check
│   └── package.json
├── infra/terraform/               # 13 リソースの IaC
│   ├── *.tf
│   ├── Justfile                   # bootstrap / plan / apply / destroy / sync-secrets
│   └── README.md
└── docs/decisions/
    ├── 0001-iac-terraform.md      # framework: なぜ Terraform 採用か
    └── 0002-template-generalization.md  # framework: instance.config.yaml + Mustache
```

## ドキュメント

- **[`docs/USAGE.md`](docs/USAGE.md)** — 詳細な利用ガイド (prerequisite / 初期セットアップ / 日常操作 / カスタマイズ / 運用 / トラブルシュート)
- [`corpus/README.md`](corpus/README.md) — corpus 命名規約 + frontmatter スキーマ
- [`worker/src/prompts/CHANGELOG.md`](worker/src/prompts/CHANGELOG.md) — System Prompt version history
- [`infra/terraform/README.md`](infra/terraform/README.md) — IaC 詳細手順 + トラブルシュート
- [`scripts/README.md`](scripts/README.md) — build-prompt / lint-domain-enum の使い方
- [`docs/decisions/0001-iac-terraform.md`](docs/decisions/0001-iac-terraform.md) — IaC 採用 ADR
- [`docs/decisions/0002-template-generalization.md`](docs/decisions/0002-template-generalization.md) — Template 化 ADR

## 設計ハイライト

- **path-based corpus 命名**: `corpus/<domain>/<repo>/<original-path>.md` で citation を GitHub URL に直接マッピング可。採番方式 (`0001-...`) の renumber hell を回避
- **Hybrid search 既定**: Vector embedding + Keyword (trigram) + RRF fusion をデフォルト ON。新 instance default の vector-only より recall が高水準
- **System Prompt versioning**: `vN.template.md` で複数版を併存、`build-prompt.ts` で render、Terraform で deploy。CHANGELOG.md で eval メトリクス込みの version history を残す
- **Cloudflare Access 必須前提**: 社内情報を扱う想定で、`/<UI>` (OTP IdP) と `/mcp` (Service Token) の 2 apps で path 別に保護
- **dual access path**: `/chat/completions` `/search` は REST API (Bearer auth、anti-abuse rate limit 回避)、`/mcp` は Public Endpoint passthrough (REST equivalent 不在のため)

## ライセンス

[MIT](LICENSE)

## 関連

- 母体: 上流 private repo の Phase 1 PoC (本テンプレートの設計・実装の検証元)
- Cloudflare AI Search: https://developers.cloudflare.com/ai-search/
- Cloudflare Terraform provider: https://github.com/cloudflare/terraform-provider-cloudflare
