# corpus/ — Cloudflare AI Search 投入対象ドキュメント

このディレクトリは **Cloudflare R2 に sync され、AI Search が retrieval 対象とするドキュメント集合**。
ここに置いたファイルは公開前提 (commit + R2 投入) として扱う。

## 役割

- **R2 sync の唯一のスコープ**。sync コマンドは `corpus/` を root に固定する
- **AI Search の retrieval 母集団**。ここに無いものは検索対象にならない
- **commit される**。機微情報は事前に `corpus-raw/` 側でサニタイズしてから持ち込む

## ファイル命名規約 (path-based)

```
corpus/<domain>/<repo>/<original-path-from-repo-root>
```

- `<domain>`: `product` / `ops` / `research`
  - 確定値は `instance.config.yaml` の `domains[].id` に集約。新規 domain 追加時は yaml を先に更新し、`bun run scripts/build-prompt.ts` で SP を再生成すること。`scripts/lint-domain-enum.ts` で yaml と本 README の同期を CI check 可能
- `<repo>`: ソースリポ名 (例: `example-app`, `internal-docs`)
- `<original-path-from-repo-root>`: ソースリポルートからの相対 path をそのまま保持
- 例: `corpus/product/example-app/docs/architecture/overview.md`
- 例: `corpus/ops/internal-docs/CLAUDE.md`

採番 (`0001-...`) は **採用しない**。citation を GitHub URL に直接マッピング可能にし、削除・追加耐性を持つため。

集約・要約物は `_digest/` 配下に隔離 (例: `corpus/product/example-app/docs/specs/_digest/specs-summary.md`)。
50KB 超の原文を AI が要約した版や、複数ファイルを集約した digest はここに置く。

## frontmatter スキーマ (必須項目)

```markdown
---
id: product/example-app/docs/architecture/overview.md
title: Example App Architecture
source: internal-doc
created_at: 2026-01-01
tags: [example-app, architecture]
status: confirmed
scope: decision
domain: product
repo: example-app
original_path: docs/SYSTEM.md
original_url: https://github.com/your-org/example-app/blob/main/docs/SYSTEM.md
as_of: 2026-01-01
reliability: high
---

# 本文 ...
```

| key | 必須 | 内容 |
|---|---|---|
| `id` | ✅ | corpus/ 以下の相対 path (拡張子込み)。R2 key と一致 |
| `title` | ✅ | 人間可読のタイトル。検索結果表示にも使える |
| `source` | ✅ | `internal-doc` / `research-report` / `external` など出所カテゴリ |
| `created_at` | ✅ | `YYYY-MM-DD`。corpus ドキュメントの作成日 (取り込み日) |
| `tags` | ⭕ | 任意の配列。検索 filter には使わないが将来の候補 |
| `status` | ✅ | `confirmed` / `active` / `draft` / `superseded` / `rejected` / `archived` / `unknown` |
| `scope` | ✅ | `decision` / `proposal` / `exploration` / `analysis` / `reference` / `narrative` |
| `domain` | ✅ | `product` / `ops` / `research` (instance.config.yaml の domains[].id と整合) |
| `repo` | ✅ | source repo 名 (`<repo>` path セグメントと一致) |
| `original_path` | ✅ | source repo ルートからの相対 path。multi-source / digest の場合は `"(multi-source, see body)"` を入れる |
| `original_url` | ✅ | GitHub URL。single-source は `/blob/main/<original_path>`、multi-source / digest は repo ルート URL |
| `as_of` | ✅ | source の as-of date (`YYYY-MM-DD`)。commit_sha が無い段階では generation 日で代用可 |
| `reliability` | ✅ | `high` / `medium` / `low`。`status: confirmed` は基本 high、`status: active` の exploration scope は low |

`status` / `scope` / `domain` は 3 軸メタデータ、
`repo` / `original_path` / `original_url` / `as_of` は **trace 系**、
`reliability` は status に紐づく信頼度軸。
System Prompt v2 系の status 認識ルール / 越境引用ルール / context override / citation 表示でこれらを参照する。

frontmatter 自体は AI Search の chunk/embed には直接使われないが、
本文の冒頭にあることでモデルに文脈として渡る + retrieval 層を将来差し替えた際に
metadata filter の根拠として残る。

## R2 sync コマンド

```bash
# 例: wrangler を使う場合
export CLOUDFLARE_ACCOUNT_ID=<your-account-id>
PREFIX=$(grep -E '^\s*prefix:' ../instance.config.yaml | awk '{print $2}')
wrangler r2 object put "${PREFIX}-corpus/<key>" --file <local-path> --remote

# 例: aws s3 sync を使う場合 (R2 は S3 互換)
aws s3 sync corpus/ s3://${PREFIX}-corpus/ --endpoint-url https://<account-id>.r2.cloudflarestorage.com
```

bulk sync は `infra/terraform/README.md` の §7 corpus 投入 を参照。

## 可視性モデル

本テンプレでは Cloudflare Access (One-time PIN with email allowlist) で保護された endpoint からのみ retrieval される。
**社員の GitHub access 権 = 検索可能性の境界** を想定している。
ただし「機密度の高い数値 (給与 / バーンレート / 未公開 KGI 等)」は
**`[REDACTED-*]` プレースホルダ化** して投入する運用とすることも可能 (運用判断)。

## してはいけないこと

- 機微情報 (個人名 / 取引先名 / 給与・財務数値 / その他高機密値) を **そのまま** 置かない
  - 機微数値だけ `[REDACTED-*]` プレースホルダに置換する暫定運用も検討可
  - 元値は corpus 外 (private notebook 等) で管理
- frontmatter なしの裸の `.md` を置かない
- 採番形式 (`0001-...`) で新規ファイルを追加しない (path-based 階層に置く)
