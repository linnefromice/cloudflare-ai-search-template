# CLAUDE.md — cloudflare-ai-search-template

Cloudflare AI Search (旧 AutoRAG) を使った社内ナレッジ検索 PoC のテンプレートリポジトリ。

## このリポジトリで作業するとき

1. README.md を読む (構成と quick start)
2. `instance.config.yaml` (clone 後に作る) が **instance 固有値の単一集約** であることを意識する
3. SP を変更する場合は **template** (`worker/src/prompts/system-prompt.vN.template.md`) を編集して `bun run scripts/build-prompt.ts --version vN` で render する。`.md` (rendered) を直接編集しない
4. インフラ変更は `infra/terraform/` で `just plan` → review → `just apply`
5. Worker コード変更は `wrangler deploy`
6. 大きな構成変更は `docs/decisions/` に ADR 形式で残す (`0003+` から)

## 必読ドキュメント

| ファイル | 役割 |
|---|---|
| [`README.md`](README.md) | 全体像 + quick start |
| [`corpus/README.md`](corpus/README.md) | corpus 命名規約 + frontmatter スキーマ |
| [`worker/src/prompts/CHANGELOG.md`](worker/src/prompts/CHANGELOG.md) | SP version 履歴 |
| [`infra/terraform/README.md`](infra/terraform/README.md) | IaC 詳細手順 |
| [`docs/decisions/0001-iac-terraform.md`](docs/decisions/0001-iac-terraform.md) | IaC 採用 ADR |
| [`docs/decisions/0002-template-generalization.md`](docs/decisions/0002-template-generalization.md) | Template 化 ADR |

## 進行ルール

- **secrets を絶対 commit しない** (`.env` / `.dev.vars` / `terraform.tfvars` 等は gitignore 済)
- **`instance.config.yaml` も commit しない** (instance 固有の prefix / account_id 等が入るため、`.example.yaml` から cp して使う)
- **rendered SP** (`system-prompt.vN.md`) は generated だが commit する (deploy 対象なので diff レビュー要)
- corpus に機微情報 (給与 / 財務数値 / 個人情報等) を **そのまま** 置かない (`[REDACTED-*]` プレースホルダ運用は corpus/README.md 参照)

## 関連 Cloudflare サービス

| サービス | 役割 |
|---|---|
| Workers Paid | プラットフォーム入場券 |
| R2 (`<prefix>-corpus`) | SoT Markdown の置き場 |
| AI Search (`<prefix>-instance`) | retrieval + ranking + answer |
| Workers AI (qwen3-embedding-0.6b) | embedding (AI Search が内部で使用、作成時固定) |
| Vectorize | ベクトル DB (AI Search が内部で使用) |
| Access × 2 apps | catchall (OTP) / `/mcp` (Service Token) |
| AI Gateway (`<prefix>-gw`) | Generation provider key 保管 + 観測層 |
| Worker proxy (`<prefix>`) | AI Search への薄い proxy |
