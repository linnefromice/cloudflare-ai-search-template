# Usage Guide

`README.md` の quick start を膨らませた詳細ガイド。新規 instance を立ち上げる場合・運用中の操作・トラブルシュートを網羅。

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [初期セットアップ](#初期セットアップ)
3. [日常的な操作](#日常的な操作)
4. [カスタマイズ](#カスタマイズ)
5. [運用](#運用)
6. [トラブルシュート](#トラブルシュート)
7. [削除 / cleanup](#削除--cleanup)
8. [Architecture references](#architecture-references)

---

## Prerequisites

### Cloudflare アカウント

| 項目 | 必須 | 備考 |
|---|---|---|
| Cloudflare アカウント | ✅ | https://dash.cloudflare.com/sign-up |
| Workers Paid plan | ✅ | $5/month。Workers AI / AI Search を使うために必要 (Free plan 不可) |
| Zero Trust 有効化 | ✅ | Dashboard → Zero Trust から enable (free tier で 50 user まで) |
| 支払い情報登録 | ✅ | Workers Paid + AI Gateway 利用に必要 |

### Generation provider のキー

AI Search の generation 層は LLM provider のキーを必要とする。default は **Google AI Studio (Gemini 2.5 Flash)** を想定:

| Provider | 取得元 | 備考 |
|---|---|---|
| **Google AI Studio** (推奨) | https://aistudio.google.com/apikey | Free tier 15 RPM / 1500 RPD で PoC 完走可 |
| OpenAI | https://platform.openai.com/api-keys | 課金登録要 |
| Anthropic | https://console.anthropic.com/settings/keys | 課金登録要 |

別 provider を使う場合: `infra/terraform/ai_search.tf` の `aisearch_model` を切替 + AI Gateway Vault に該当 provider の key を投入 (Dashboard → AI → AI Gateway → `<prefix>-gw` → Vault → Add Provider Key)。

### ローカル環境

| ツール | バージョン目安 | インストール |
|---|---|---|
| `terraform` | 1.5+ | `brew install hashicorp/tap/terraform` |
| `just` | 1.x | `brew install just` |
| `bun` | 1.x | `curl -fsSL https://bun.sh/install \| bash` |
| `wrangler` | 3.x+ | `npm install -g wrangler` |
| `gh` | (任意) | `brew install gh` (Cloudflare 操作には不要、PR 用) |

### Cloudflare API Token (Terraform 用)

Dashboard → My Profile → API Tokens → Create Token → **Custom token** で以下 scope を持たせる:

| 領域 | 権限 |
|---|---|
| Account → AI Search | Edit + Read + Run + Index |
| Account → R2 Storage | Edit |
| Account → Workers Scripts | Edit |
| Account → Access (Apps and Policies) | Edit |
| Account → Access (Identity Providers and Groups) | Edit |
| Account → Access (Service Tokens) | Edit |
| Account → AI Gateway | Edit |

> **NOTE**: Cloudflare の standard "Edit Cloudflare Workers" template には AI Search や Access が含まれない。**Custom token** で個別 scope を付ける必要がある。

token UUID は `/user/tokens/verify` で取得:

```bash
curl -s -H "Authorization: Bearer <YOUR_TOKEN>" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq -r '.result.id'
```

---

## 初期セットアップ

### Step 1: clone + 設定ファイル準備

```bash
git clone https://github.com/linnefromice/cloudflare-ai-search-template.git
cd cloudflare-ai-search-template

# instance 固有値テンプレを cp
cp instance.config.example.yaml instance.config.yaml
$EDITOR instance.config.yaml
```

`instance.config.yaml` で必須の書換:

| Key | 説明 | 取得方法 |
|---|---|---|
| `infra.prefix` | 全 Cloudflare resource の prefix | 任意の英小文字 + `-` (例: `my-aisearch-poc`)。`<prefix>-corpus` `<prefix>-instance` 等で派生される |
| `infra.cloudflare_account_id` | account ID | Dashboard 右上の workers icon ホバー or `wrangler whoami` |
| `infra.workers_dev_subdomain` | `*.workers.dev` のサブドメイン | Dashboard → Workers & Pages → 右上 account 名の下に表示 |
| `infra.otp_email_domain` | OTP IdP 許可ドメイン | 自社のメールドメイン (例: `acme-corp.com`) |
| `infra.operator_email` | catchall app の許可 user | あなたの email |
| `org.name` / `org.short_name` | 組織名 (System Prompt と UI に注入) | 自由記述 |
| `domains[]` | 検索対象ドメインの分類軸 | 後述「カスタマイズ § domain 追加」参照 |

`sp_extras` は instance 固有の SP 例外 (brand-name 警戒等) を入れる場所。空配列で OK。

### Step 2: corpus 準備

`corpus/<domain>/<repo>/<original-path>.md` の path-based 命名で markdown を配置:

```bash
mkdir -p corpus/product/my-app/docs
$EDITOR corpus/product/my-app/docs/architecture.md
```

frontmatter スキーマと命名規約は [`corpus/README.md`](../corpus/README.md) 参照。**13 必須フィールド** (`id` / `title` / `source` / `created_at` / `tags` / `status` / `scope` / `domain` / `repo` / `original_path` / `original_url` / `as_of` / `reliability`) 全部埋める。

> 機微情報 (給与 / 財務数値 / 個人情報) を **そのまま corpus に置かない**。`[REDACTED-*]` プレースホルダ運用は corpus/README.md §してはいけないこと参照。

### Step 3: Worker proxy 設定

```bash
cd worker
cp wrangler.toml.example wrangler.toml
$EDITOR wrangler.toml
```

`name` と `account_id` を `instance.config.yaml` の `infra.prefix` / `infra.cloudflare_account_id` と揃える。`AI_SEARCH_INSTANCE` UUID は terraform apply 後に取得するので一旦そのまま。

```bash
# Worker script を Cloudflare に登録 (subdomain binding 前段の prerequisite)
wrangler deploy
```

> `wrangler login` 未実行の場合は OAuth 認証フローへ。

### Step 4: Terraform で 13 リソース作成

```bash
cd ../infra/terraform
cp .env.example .env
$EDITOR .env
# TF_VAR_cloudflare_api_token   : 上記 step で発行した token
# TF_VAR_cloudflare_api_token_id: token UUID

just bootstrap
# = build-prompt (template → SP) + terraform init + plan + apply
```

apply 後、output に Service Token credential や AI Search instance UUID が表示される。

### Step 5: Worker secret + .env sync

```bash
just sync-secrets
# = TF_VAR_cloudflare_api_token を AI_SEARCH_API_TOKEN として wrangler secret put
#   + Service Token credential / AI Search instance UUID を root .env に書込
```

このとき表示される `AI_SEARCH_INSTANCE = "..."` を `worker/wrangler.toml` の対応行に貼り付け、再 deploy:

```bash
cd ../../worker
$EDITOR wrangler.toml   # AI_SEARCH_INSTANCE = "<UUID>" に更新
wrangler deploy
```

### Step 6: AI Gateway Vault に provider key 投入

Dashboard → AI → AI Gateway → `<prefix>-gw` → Settings → Vault → **Add Provider Key**:

- Provider: `Google AI Studio` (default の Gemini 2.5 Flash 利用時)
- API Key: 上記 prerequisites で取得した key

別 provider を使う場合は同じ画面で対応 provider を選択。

### Step 7: corpus を R2 に sync

```bash
cd corpus
export CLOUDFLARE_ACCOUNT_ID=<your-account-id>
PREFIX=$(grep -E '^\s*prefix:' ../instance.config.yaml | awk '{print $2}')
for f in $(find . -type f -name '*.md' ! -name 'README.md'); do
  wrangler r2 object put "${PREFIX}-corpus/${f#./}" --file="$f" --remote
done
```

数秒〜数十秒で AI Search が auto-watch で再 index する。Dashboard → AI → AI Search → `<prefix>-instance` → **Indexed: N/N** で確認。

### Step 8: 動作確認

```bash
cd ../infra/terraform
WORKER_URL=$(terraform output -raw worker_url)
open $WORKER_URL
```

- Cloudflare Access の **OTP プロンプト** が出る
- 設定した `operator_email` (or `otp_email_domain` の任意の email) を入力
- メールに 6 桁コード届く → 入力 → **chat UI** が表示
- 質問を投げて corpus に基づいた回答 + citation が返ってくれば成功

---

## 日常的な操作

### corpus を更新する

```bash
$EDITOR corpus/<domain>/<repo>/<path>.md   # 編集 or 新規追加
wrangler r2 object put "${PREFIX}-corpus/<key>" --file <local-path> --remote
```

R2 の auto-watch (~30 秒) で AI Search が再 index する。Indexed 数を Dashboard で確認。

### corpus を削除する

```bash
wrangler r2 object delete "${PREFIX}-corpus/<key>" --remote
```

R2 から消えると AI Search も次の auto-watch で index から外す。

### 全件 resync を強制

```bash
curl -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/ai-search/namespaces/default/instances/${PREFIX}-instance/jobs" \
  -H "Authorization: Bearer ${TF_VAR_cloudflare_api_token}"
```

### System Prompt を変更する

1. **template を編集** (`worker/src/prompts/system-prompt.v2.1.template.md`)
   - **`.md` (rendered)** を直接編集してはいけない (build artifact)
2. `bun run scripts/build-prompt.ts --version v2.1` で render
3. `terraform apply` で AI Search instance に deploy
4. `worker/src/prompts/CHANGELOG.md` に entry 追加

```bash
# 編集 → render → deploy
$EDITOR worker/src/prompts/system-prompt.v2.1.template.md
bun run scripts/build-prompt.ts --version v2.1
cd infra/terraform && just apply
```

### Worker コードを変更する

```bash
$EDITOR worker/src/index.ts
cd worker && wrangler deploy
```

Worker は Terraform 範囲外 (wrangler 主導)。terraform apply は不要。

### インフラ設定を変更する

```bash
$EDITOR infra/terraform/<...>.tf
cd infra/terraform && just plan && just apply
```

`instance.config.yaml` を変更した場合も同じ flow (terraform は yamldecode で参照)。

### Service Token をローテーション

```bash
cd infra/terraform
# token resource を taint
terraform taint cloudflare_zero_trust_access_service_token.mcp
just apply
just sync-secrets   # 新 client_id / secret を Worker secret + .env に再投入
```

---

## カスタマイズ

### domain を追加する

「product / ops / research」以外を追加したい場合:

1. `instance.config.yaml` の `domains[]` に新 entry 追加:
   ```yaml
   domains:
     - id: docs
       label: "ドキュメント全般"
       primary_repos: [my-repo]
     - id: research      # ← 追加
       label: "リサーチ"
       primary_repos: [research-repo]
   ```
2. `corpus/README.md` の `<domain>` enum 説明行を更新 (人手):
   ```markdown
   - `<domain>`: `docs` / `research`
   ```
3. `bun run scripts/lint-domain-enum.ts` で yaml と README の整合確認
4. `bun run scripts/build-prompt.ts` で SP 再 render (新 domain が table に反映)
5. `cd infra/terraform && just apply` で AI Search instance に deploy
6. corpus に新 domain のファイルを追加 (path: `corpus/research/...`)

### 別 LLM provider に切替

`infra/terraform/ai_search.tf` の `aisearch_model` を変更:

```hcl
# 変更例
# aisearch_model = "google-ai-studio/gemini-2.5-flash"
aisearch_model = "openai/gpt-4o-mini"      # OpenAI
# aisearch_model = "anthropic/claude-3-5-haiku-20241022"   # Anthropic
```

`just apply` 後、AI Gateway Vault に該当 provider の key を投入 (Dashboard 操作)。

### Reranking を ON にする

```hcl
# infra/terraform/ai_search.tf
reranking       = true
reranking_model = "@cf/baai/bge-reranker-base"
```

`just apply`。Reranking ON は corpus の性質によっては Recall が劣化することがある (digest 比率が高い corpus 等)。eval を取って判断推奨。

### 検索動作を tune

| パラメータ | デフォルト | 効果 |
|---|---|---|
| `chunk_size` | 512 | chunk のトークン数。大きいと context 増、小さいと recall 上げやすい |
| `chunk_overlap` | 30 | chunk 重なりトークン数 (0-30 範囲) |
| `max_num_results` | 10 | retrieval 上限 (top-N) |
| `keyword_match_mode` | `or` | `or` / `and`。and は厳密 hit |
| `cache` | false | response caching (`cache_threshold` で類似度閾値) |

変更時は **full re-index が走る** ことに注意 (provider doc 警告)。

---

## 運用

### eval (retrieval 品質計測)

本テンプレートには eval scripts は含めていない (instance 固有のため)。

実装する場合の参考:

```typescript
// scripts/eval.ts (構造のみの例)
import { parse } from "yaml";
import { readFileSync } from "node:fs";

const questions = parse(readFileSync("docs/context/eval/questions.yaml", "utf8"));
for (const q of questions) {
  const resp = await fetch(`https://api.cloudflare.com/.../instances/${INSTANCE}/chat/completions`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messages: [{ role: "user", content: q.query }] }),
  });
  // ... metrics 集計
  await new Promise(r => setTimeout(r, 6000));   // Gemini Free Tier 15 RPM 対策
}
```

eval セットの設計指針:
- `expected_sources`: top-5 に出てほしい citation source (path-based key)
- `forbidden_in_top5_sources`: 出てほしくない source (brand-name spam 検証)
- `expected_response_pattern`: response 内容の正規表現
- `forbidden_in_response`: 応答に出てほしくないパターン

### CI 推奨 step

`.github/workflows/ci.yaml` を追加する場合の最小構成:

```yaml
- run: bun install --cwd scripts
- run: bun run scripts/build-prompt.ts --check         # SP template/render の drift 検知
- run: bun run scripts/lint-domain-enum.ts             # domains[] と corpus README の同期 check
- run: bun test scripts/build-prompt.test.ts            # unit test
- run: terraform -chdir=infra/terraform fmt -check
- run: terraform -chdir=infra/terraform validate
```

### MCP 連携 (Claude Desktop)

Service Token で `/mcp` endpoint を保護しているため、Claude Desktop に Service Token credentials を渡す必要がある。

`~/Library/Application Support/Claude/claude_desktop_config.json` に追加:

```json
{
  "mcpServers": {
    "my-instance": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "https://<prefix>.<workers_dev_subdomain>.workers.dev/mcp",
        "--header", "CF-Access-Client-Id:<CLIENT_ID>",
        "--header", "CF-Access-Client-Secret:<CLIENT_SECRET>"
      ]
    }
  }
}
```

`<CLIENT_ID>` / `<CLIENT_SECRET>` は `just sync-secrets` 後の root `.env` に書かれる `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET`。

---

## トラブルシュート

### `terraform apply` が `system-prompt.v2.1.md not found` で fail

build-prompt.ts が走っていない。`just bootstrap` を使うか、`just build-prompt` を先に実行:

```bash
cd infra/terraform && just build-prompt && just apply
```

### `cloudflare_workers_script_subdomain` で「script not found」エラー

Worker script が wrangler でまだ deploy されていない。先に:

```bash
cd worker && wrangler deploy
cd ../infra/terraform && just apply
```

### `cloudflare_ai_search_token` を destroy 後に再作成できない

token resource は `terraform import` 非対応 (provider 制約)。`just destroy && just bootstrap` の greenfield 再構築で対応。

### R2 bucket destroy が `409 BucketNotEmpty` で fail

corpus を先に空にする:

```bash
cd corpus
PREFIX=$(grep -E '^\s*prefix:' ../instance.config.yaml | awk '{print $2}')
env -u CLOUDFLARE_API_TOKEN bash -c "
  for f in \$(find . -type f -name '*.md' ! -name 'README.md'); do
    wrangler r2 object delete \"${PREFIX}-corpus/\${f#./}\" --remote
  done
"
cd ../infra/terraform && just destroy
```

`env -u CLOUDFLARE_API_TOKEN` は wrangler を OAuth fallback させるため (TF token は R2 scope を持たない場合があるので明示的に外す)。

### Access OTP メールが届かない

- email domain が `infra.otp_email_domain` と一致するか確認
- spam フォルダ確認
- Dashboard → Zero Trust → Access → Logs で auth event を確認

### Gemini が `429 Resource Exhausted`

Gemini Free Tier の 15 RPM / 1500 RPD 制限に達した。eval scripts では `QUERY_DELAY_MS=6000` 以上の sleep を入れる。本格運用は paid tier or 別 provider に切替。

### `chunk_overlap value must be between 0 and 30`

provider 5.x の schema validation に hit。`infra/terraform/ai_search.tf` の `chunk_overlap` を 0-30 範囲に。

### config を変えても `terraform plan` で差分が出ない

`instance.config.yaml` の編集後 `terraform refresh` を試す。それでも出ない場合は yamldecode のキャッシュを疑い、`terraform init -upgrade` で provider を再 init。

---

## 削除 / cleanup

### 全リソース drop

```bash
# 1. R2 bucket を空に (上記トラブルシュート参照)
# 2. terraform destroy
cd infra/terraform && just destroy
# 3. wrangler delete で worker script を削除
cd ../../worker && wrangler delete
```

ローカル state は `infra/terraform/terraform.tfstate*` に残るので、archive するか削除。

### AI Gateway Vault key の管理

`terraform destroy` で AI Gateway resource ごと削除されると Vault の provider key も消える。再構築時は再投入。控えておきたい場合は **destroy 前に Dashboard で Vault key を Reveal して保管**。

---

## Architecture references

| ドキュメント | 内容 |
|---|---|
| [`docs/decisions/0001-iac-terraform.md`](decisions/0001-iac-terraform.md) | なぜ Terraform を採用したか (vs Pulumi / CDKTF / SST / Alchemy / wrangler のみ) |
| [`docs/decisions/0002-template-generalization.md`](decisions/0002-template-generalization.md) | `instance.config.yaml` + Mustache テンプレ化の設計判断 (L1-L6 layering) |
| [`worker/src/prompts/CHANGELOG.md`](../worker/src/prompts/CHANGELOG.md) | System Prompt の version 履歴と設計理念 |
| [`corpus/README.md`](../corpus/README.md) | corpus 命名規約 + frontmatter スキーマ |
| [`infra/terraform/README.md`](../infra/terraform/README.md) | terraform 詳細 + 運用 runbook |
| [`scripts/README.md`](../scripts/README.md) | build-prompt / lint-domain-enum 仕様 |

---

## ライセンス

[MIT](../LICENSE)
