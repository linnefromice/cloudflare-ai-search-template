# infra/terraform — Cloudflare IaC

Cloudflare アセット **13 リソース** の Terraform 宣言。設計は [`docs/decisions/0001-iac-terraform.md`](../../docs/decisions/0001-iac-terraform.md) を参照。

## 構成

| ファイル | 内容 |
|---|---|
| `versions.tf` | Terraform >= 1.5、cloudflare provider ~> 5 |
| `providers.tf` | provider 設定 |
| `variables.tf` | 入力変数 (cloudflare_api_token 等) |
| `main.tf` | locals (resource 名は `instance.config.yaml` の `infra.prefix` から派生) |
| `outputs.tf` | sync 用の outputs |
| `r2.tf` | R2 bucket × 1 |
| `ai_search.tf` | AI Gateway + AI Search instance + token (3) |
| `access.tf` | OTP IdP + Service Token + apps × 2 + policies × 2 (6) |
| `worker.tf` | Worker subdomain × 1 |
| `Justfile` | 運用 recipe (build-prompt → init → plan → apply の bootstrap 含む) |

System Prompt は `cloudflare_ai_search_instance.system_prompt_aisearch` で `worker/src/prompts/system-prompt.v2.1.md` (build 結果) を直接読み込む。

## セットアップ

### 1. Tools

```bash
brew install hashicorp/tap/terraform just
# bun: https://bun.sh/ (worker / scripts 用)
```

### 2. instance.config.yaml を準備

```bash
# repo root で
cp instance.config.example.yaml instance.config.yaml
# instance.config.yaml を自分の値で書き換え (infra.prefix / cloudflare_account_id 等)
```

### 3. API Token 発行

Cloudflare Dashboard → My Profile → API Tokens → Create Token →
custom token で以下 scope:

- AI Search: Edit
- R2: Edit
- Workers Scripts: Edit
- Access (Apps and Policies + IdP/Groups + Service Tokens): Edit
- AI Gateway: Edit

### 4. .env

```bash
cp .env.example .env
# .env に TF_VAR_cloudflare_api_token と TF_VAR_cloudflare_api_token_id を設定
```

`TF_VAR_cloudflare_api_token_id` は token UUID。以下で取得:

```bash
curl -s -H "Authorization: Bearer $TF_VAR_cloudflare_api_token" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq -r '.result.id'
```

### 5. Bootstrap

```bash
just bootstrap
# = build-prompt + terraform init + plan + apply
```

cutover 時 (greenfield 状態) は `apply` で 13 リソースが新規作成される。**Worker script が wrangler でまだ deploy されていない場合**は `cloudflare_workers_script_subdomain` で「script not found」エラーになる → 先に `cd worker && wrangler deploy` を済ませてから再 apply。

### 6. Secret + .env sync (Worker 側に反映)

```bash
just sync-secrets
# = TF_VAR_cloudflare_api_token を AI_SEARCH_API_TOKEN として
#   wrangler secret put + Service Token credential を root .env に書込
```

### 7. wrangler.toml の AI_SEARCH_INSTANCE 更新

`just sync-secrets` の最後に表示される指示に従い、`worker/wrangler.toml` の
`AI_SEARCH_INSTANCE` 行を新 UUID に書き換え、`cd worker && wrangler deploy`。

### 8. corpus 投入

```bash
cd ../../corpus
export CLOUDFLARE_ACCOUNT_ID=<your-account-id>
PREFIX=$(grep -E '^\s*prefix:' ../instance.config.yaml | awk '{print $2}')
for f in $(find . -type f -name '*.md' ! -name 'README.md'); do
  wrangler r2 object put "${PREFIX}-corpus/${f#./}" --file="$f" --remote
done
```

## 運用

| 操作 | コマンド |
|---|---|
| Plan を見る | `just plan` |
| Apply | `just apply` |
| Destroy (greenfield 再構築) | `just destroy` |
| 出力一覧 | `just outputs` |
| 特定 output | `just show-output ai_search_instance_uuid` |

## State 管理

- ローカル `terraform.tfstate` のみ、`.gitignore` 済
- ラップトップ紛失で state ロスト → `just destroy` 不可になるが、Dashboard で手動削除 + `just bootstrap` で復旧可能
- multi-developer 化のタイミングで R2 backend (S3 互換) に移行を検討 (ADR §state backend 参照)

## トラブルシューティング

### `cloudflare_workers_script_subdomain` で「script not found」エラー

Worker script 本体は wrangler が deploy する。順序:
1. `wrangler deploy` (worker/ で実行) → script を Cloudflare に登録
2. `just apply` → subdomain を Terraform で有効化

### `cloudflare_ai_search_token` が destroy 後に再作成できない

token resource は `terraform import` 非対応 (provider 制約)。
greenfield 再構築は `just destroy && just bootstrap` で問題なし。

### `chunk_overlap value must be between 0 and 30` 等の validate エラー

provider 5.x は schema-driven validation を持つ。`terraform providers schema -json | jq '.provider_schemas."registry.terraform.io/cloudflare/cloudflare".resource_schemas.<resource>'` で許容値を確認して調整する。

### `system-prompt.v2.1.md not found` で apply が fail

`just bootstrap` の `build-prompt` step が走っていない (= 別 recipe 経由で apply してる)。`just build-prompt` を先に走らせるか、`just bootstrap` で full chain を実行する。
