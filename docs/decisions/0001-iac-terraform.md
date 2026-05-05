# ADR 0001: Cloudflare アセットを Terraform で管理する

- **Status**: Accepted
- **Date**: framework decision (initial)
- **Phase**: Phase 1 (本テンプレ)

## Context

Cloudflare AI Search PoC の基盤として **13 Terraform リソース相当** が必要:

- R2 bucket × 1 (corpus 置き場)
- AI Search instance × 1 + token × 1
- AI Gateway × 1
- Worker subdomain × 1
- Access apps × 2 + policies × 2
- OTP IdP × 1
- Service Token × 1

これらを Dashboard と wrangler CLI の手作業で構築すると以下が顕在化する:

1. **再現性なし**: 「Day 1 setup」が手順書頼みで何分かかるか未知。新環境構築 (dev / staging) や障害復旧時の負荷が不明
2. **drift 検知不能**: Dashboard で誰かが設定変更しても気付けない
3. **Phase 2 (組織 repo / multi-developer) への橋渡し不足**: 現行構成を「コピペ可能な宣言ファイル」として持ち出せない
4. **Service Token / API token のローテーション運用が未確立**: 期限切れ対応や緊急 revoke のフローが Dashboard 操作前提

PoC のうちに **IaC 化のスタックと運用フローを確定** させる必要がある。

## Decision

**Cloudflare 公式 Terraform provider (`cloudflare/terraform-provider-cloudflare ~> 5`) を採用** し、`infra/terraform/` 配下で 13 リソースを管理する。

### スコープ境界

| 領域 | 管理ツール | 理由 |
|---|---|---|
| R2 bucket / AI Search instance + token / AI Gateway / Worker subdomain / Access × 2 apps + 2 policies + OTP IdP / Service Token (= **13 リソース**) | **Terraform** | インフラ宣言。低頻度変更、宣言的管理が効く |
| AI Search instance の System Prompt (`system_prompt_aisearch`) | **Terraform** (instance resource の attribute 経由) | provider 5.x で直接 attribute として exposed。`worker/src/prompts/system-prompt.v2.1.md` (build-prompt.ts の render 結果) を `file()` 関数で読み込んで渡す形で declarative に管理 |
| Worker script 本体 + bindings + secret 値 | **wrangler** | 高頻度変更 (実装中)、Terraform `apply` サイクルだと開発が重くなる |
| corpus Markdown ファイル本体 (R2 オブジェクト) | **wrangler r2 object put** または GH Actions | Terraform で R2 オブジェクトを管理するのは anti-pattern |
| Cloudflare アカウント / Workers Paid 契約 / API Token 発行 | **人間 + Dashboard** | Terraform 管轄外 |

### state backend

- **初期はローカル + gitignore**: 単独開発 + greenfield 再構築可な前提では、state ロスト = `terraform apply` し直しで復旧可能なので外部 backend のオーバーヘッドが割に合わない
- **multi-developer / multi-env 化のタイミングで R2 backend (S3 互換) に移行**: bootstrap 時の chicken-egg 問題は「最初の R2 bucket だけ wrangler で手動作成 → backend 設定 → import」で回避

### secret 管理

- **入力** (Terraform へ): `infra/terraform/.env` (gitignored) に `TF_VAR_cloudflare_api_token` と `TF_VAR_cloudflare_api_token_id`
- **出力** (Terraform から他所へ): Service Token credential / AI Search instance UUID / AI Search API token を `terraform output` で取り出し、`just sync-secrets` recipe が `wrangler secret put` と root `.env` 追記を自動化
- 新規ツール導入: `just` (`brew install just`) — Make よりシンプル、既存 bun スタックへの追加負荷小

### ファイル構成

```
infra/terraform/
├── README.md           # セットアップ手順 + 運用 runbook
├── .gitignore          # *.tfstate*, .terraform/, .env, *.tfvars
├── .env.example
├── versions.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── main.tf             # locals + naming convention (instance.config.yaml から派生)
├── r2.tf               # 1 リソース
├── ai_search.tf        # 3 リソース (Gateway / token / instance)
├── access.tf           # 6 リソース (apps 2 + policies 2 + IdP 1 + Service Token 1)
├── worker.tf           # 1 リソース (subdomain enable)
└── Justfile            # build-prompt / bootstrap / plan / apply / destroy / sync-secrets
```

`modules/` 切りはしない (13 リソース規模で over-engineering)。multi-env 化する時点で導入を再検討。

### 主要設計値

| 項目 | 値 |
|---|---|
| Cloudflare provider version | 最新 stable を採用、`~> 5` 等で minor pin |
| AI Search embedding model | `@cf/qwen/qwen3-embedding-0.6b` (作成時固定、変更不可) |
| AI Search generation model | `google-ai-studio/gemini-2.5-flash` via AI Gateway (default、変更可) |
| AI Search reranking | `false` (baseline) |
| Access session duration | `8h` |
| Service Token duration | `8760h` (1 年) |

## Consequences

### Positive

- **再現性**: `just bootstrap` で 13 リソースが ~2 分で復旧可能 (手動 setup の数時間から短縮)
- **drift 検知**: `terraform plan` で Dashboard 側変更が即可視化
- **判断ログ**: Access policy / OTP allowlist / AI Search の hidden defaults 等、Dashboard では暗黙だった設定値が宣言ファイルに明記される
- **「インフラ vs アプリ」の境界が明確**: Worker コード変更は wrangler、インフラ + System Prompt 変更は terraform、と責務分離

### Negative / Trade-offs

- **新規ツール導入**: `terraform` (HashiCorp BSL ライセンス) と `just` を `brew install` が必要
- **学習コスト**: HCL の記法と Cloudflare provider の resource schema を覚える必要がある
- **provider のラグ**: AI Search の hidden config (`source_params` / `index_method` / `retrieval_options` の nested schema) は docs に未開示で、実装時に `terraform providers schema -json` で実調査する必要あり
- **`cloudflare_ai_search_token` が `terraform import` 非対応**: greenfield 再構築前提で回避するが、「既存 token を温存したい」要件が出たら工夫が必要
- **state ロスト時のリスク**: ローカル state 運用ではラップトップ紛失で state も消える → ただし greenfield 再構築可な設計なので業務継続性影響は小

## Alternatives Considered

### A. 現状維持 (Dashboard + wrangler のみ)

- 棄却理由: 手作業が積み上がる。drift 検知できない問題は時間が経つほど悪化

### B. OpenTofu

- 採用候補。Cloudflare provider は両方で同一動作、ライセンス (BSL) 懸念は商用利用時の問題で個人 PoC では実害なし
- provider 設定 1 箇所の変更で OpenTofu に切替可能なので、本テンプレを fork して切替可

### C. Pulumi (TS)

- 魅力: bun + TS スタックと言語統一、loop / 抽象化が自然、AWS / GCP も同じコードで管理可能
- 棄却理由: Cloudflare 公式 provider が Terraform 起点 (API spec から自動生成) で、新機能 (AI Search 等) の追従は Terraform が最速。Pulumi は wrapping 経由で常にラグあり

### D. CDKTF (CDK for Terraform)

- 棄却理由: Pulumi の下位互換に見える (HCL を TS で書いて再度 Terraform 経由する 1 段増えるだけ)。素直に HCL でよい

### E. SST v3 (ION)

- 棄却理由: フルスタックアプリ構築が主目的、純 Cloudflare インフラ管理には重い

### F. Alchemy

- 魅力: bun ネイティブ、Cloudflare 特化の新興 OSS、code-first
- 棄却理由: 新しすぎて AI Search / Access の対応状況が未調査、長期メンテ不安

### G. wrangler.toml + REST API script のみ

- 棄却理由: Access / AI Gateway / AI Search を REST で書く工数が結局重く、state 管理を自前実装するなら Terraform を使った方が早い

## Out of Scope (本 ADR の対象外)

- multi-env (dev / staging / prod) 構成: state backend 移行と同時に検討
- Worker code の Terraform 化: wrangler 主導を維持
- R2 オブジェクト本体の管理: wrangler / GH Actions に委譲
