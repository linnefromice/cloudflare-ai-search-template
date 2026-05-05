# ADR 0002: Template generalization (instance.config.yaml + Mustache)

- **Status**: Accepted
- **Date**: framework decision
- **Related**: ADR 0001 (IaC Terraform 化) / `worker/src/prompts/CHANGELOG.md` (SP versioning)

## 1. 動機と goal

### 1.1 動機

Terraform 化 (ADR 0001) と SP v2 系の merge で本テンプレの構造が一段安定した。ここで「instance 固有値」と「汎用ロジック」を分離しておくことで、別 instance 立ち上げ時の流用コストを大幅に下げる。

### 1.2 Goal

- `instance.config.yaml` 1 ファイルの書き換え + corpus / eval セットの差し替え + 本テンプレの clone のみで、別 instance を立ち上げられる状態
- 「変数化」の対象を以下 5 層に絞る:

| 層 | 内容 | 優先度 |
|---|---|---|
| L1 | インフラ命名 (prefix, account_id, OTP domain, operator email, workers.dev subdomain) | 必須 |
| L2 | SP の組織固有部分 (組織名、domain 定義表、brand-name 警戒ルール) | 推奨 |
| L3 | corpus 分類軸 (`<domain>` enum、SP 内の domain mapping) — L2 とセットで一貫させる | 推奨 |
| L4 | eval セットの場所 (questions YAML) | 推奨 |
| L6 | Worker UI の文字列 (page title) | 推奨 |

### 1.3 Non-goal

| 項目 | 理由 |
|---|---|
| L5 (`docs/context/` や `SESSION-NOTES.md` の template/instance 分離) | 設計コスト過大。clone 時の扱いは README ガイドで明文化する |
| Schema 駆動の code-gen (案 B、後述) | 第 3 / 第 4 のクローンが現れた時点で再検討。現時点では overkill |
| `embedding_model` / `aisearch_model` 等の AI 設定の変数化 | 変更操作が重い (AI Search instance 再作成 + corpus 再 index)。誤操作防止のため意図的に terraform hardcoded のまま残す |
| `status` / `scope` / `reliability` の enum の変数化 | これらは AI Search PoC というツール側の framework 規約であり instance 固有ではない |

---

## 2. 採用方針: 案 A — 軽量テンプレート (文字列置換型)

検討した 3 案:

| 案 | 概要 | 採否 |
|---|---|---|
| A | `instance.config.yaml` + Mustache テンプレで SP/terraform/Worker を render | **採用** |
| B | スキーマ駆動 code-gen (schema → SP/corpus README/frontmatter validator/terraform locals を一括生成) | 不採用 (overkill、作業量 2-3 倍) |
| C | tfvars + README ガイドのみ (L2/L3/L4 はコード変更せず手順書化) | 不採用 (clone 時に元の値のまま deploy するリスクが残る) |

### 2.1 案 A を選ぶ理由

1. **clone 回数の想定 (1-2 回) と案 B のスキーマ駆動投資の対比で、A の労力対効果が最良**。3 回目のクローンで pain が顕在化したら B に進化させやすい構造になっている
2. **terraform 化のおかげで L1 はほぼ完成形に近い** (残るは prefix と URL hardcode の変数化のみ)。SP の templating だけ追加すれば全体像が揃う
3. **既存の SP versioning (v1 / v1.1 / v2 / v2.1) を温存できる**。テンプレ化は version の上に乗る orthogonal な操作
4. **Mustache の logic-less 制約が「過剰構造化」への踏み絵になる**。SP は自然言語の柔軟性で生きているので、表現力の高いテンプレ言語 (Handlebars / Jinja2) を入れるとテンプレ側にロジックが滲み出す

---

## 3. 設計

### 3.1 ファイル構成

```
<repo-root>/
├── instance.config.yaml           ← 【instance】各 instance 固有値の単一集約 (gitignore 推奨)
├── instance.config.example.yaml   ← 【framework】テンプレ利用者向けサンプル (commit)
├── scripts/
│   ├── build-prompt.ts            ← config + SP テンプレ → 最終 SP
│   └── lint-domain-enum.ts        ← yaml と corpus README の domain enum 同期 check
├── worker/
│   └── src/prompts/
│       ├── system-prompt.v2.template.md   ← Mustache template
│       ├── system-prompt.v2.1.template.md ← Mustache template (current)
│       ├── system-prompt.v2.1.md          ← generated (build-prompt.ts の出力、deploy 対象)
│       └── CHANGELOG.md
└── infra/terraform/main.tf        ← prefix / account_id / OTP domain 等を yamldecode で参照
```

### 3.2 重要な設計判断

1. **`instance.config.yaml` をリポルートに置く**: terraform / SP build / Worker / docs README が全部ここを見る形。テンプレ利用者は **このファイル 1 つを書き換えればだいたい終わる** ことを目標にする
2. **`system-prompt.vN.md` (rendered) を commit する**: 理由は (a) AI Search Settings には deploy 後のものが入るので diff レビューが要る (b) Worker は SP を bundle しないのでビルド失敗が即座に発覚しない。commit 前に build-prompt.ts の `--check` モードを CI で必須化
3. **terraform.tfvars と instance.config.yaml の二重管理は避ける**: terraform 側で `yamldecode(file("../../instance.config.yaml"))` する。secrets (Cloudflare API token 等) だけ tfvars or env で別管理
4. **secrets と config の分離原則**: `instance.config.yaml` には secrets を絶対入れない。Cloudflare API token / Service Token client_secret / 各種 API key 等は `.env` 側で管理

### 3.3 `instance.config.yaml` のスキーマ

L1 / L2 / L3 / L4 / L6 がこのファイル 1 つを参照する。

```yaml
# === L1: インフラ命名 ===
infra:
  prefix: my-aisearch-poc                  # 全 Cloudflare resource の prefix
  cloudflare_account_id: <YOUR_CLOUDFLARE_ACCOUNT_ID>
  workers_dev_subdomain: <YOUR_WORKERS_DEV_SUBDOMAIN>
  otp_email_domain: example.com            # OTP IdP 許可ドメイン
  operator_email: you@example.com          # catchall app の許可 user

# === L6: UI 文字列 ===
ui:
  page_title: "My AI Search PoC"

# === L2 + L3: 組織 / ドメイン定義 (SP テンプレと corpus 両方が参照) ===
org:
  name: "My Organization"
  short_name: "MyOrg"

# corpus の分類軸 + SP の domain mapping table の単一定義
domains:
  - id: docs
    label: "ドキュメント全般"
    primary_repos: [my-repo]

# SP rule 4「絶対 NG パターン」のうち instance 固有部分
sp_extras:
  brand_names_to_deprioritize: []
  noisy_path_examples: []

# === L4: eval ===
eval:
  questions_files:
    - docs/context/eval/questions.yaml
  default: docs/context/eval/questions.yaml
```

### 3.4 スキーマ設計の判断

1. **`domains` を構造化 list にした理由**: SP の table と corpus README の enum 説明と corpus 命名の `<domain>` セグメントが **3 箇所で同じ情報を保持している現状** (drift の温床) を single source 化するため。`scripts/lint-domain-enum.ts` で yaml と corpus README の同期を CI check
2. **`sp_extras` で逃げ道を残す**: brand-name 警戒ルールのような instance 固有の例外は schema 化しきれない。薄い list で吸収して SP テンプレ側でループ展開 (案 B 化を防ぐ意図的なゆるさ)
3. **enum を framework 規約として固定化**: `status` / `scope` / `reliability` は instance に依存しない
4. **AI モデル設定を意図的に config から外す**: `embedding_model` / `aisearch_model` / `chunk_size` 等は terraform hardcoded のまま。「変える操作の重さ」 (instance 再作成) を考慮し、軽く YAML で切り替えられる場所には置かない

### 3.5 SP ビルドパイプライン (`scripts/build-prompt.ts`)

#### CLI

```
bun run scripts/build-prompt.ts                    # 最新 vN を generate
bun run scripts/build-prompt.ts --version v2       # 明示指定
bun run scripts/build-prompt.ts --check            # generated と template+config 整合チェック (CI 用)
```

#### 入出力

```
入力:
  - instance.config.yaml
  - worker/src/prompts/system-prompt.vN.template.md  (default: 最新 vN)
出力:
  - worker/src/prompts/system-prompt.vN.md           (generated, commit 対象)
```

#### 仕様

1. **テンプレート言語**: [Mustache](https://mustache.github.io/) を採用。依存は `mustache` 1 パッケージのみ。logic-less = テンプレ側に処理を書けない制約を意図的に効かせる
2. **生成ファイル末尾に footer を必ず注入**: `<!-- generated by scripts/build-prompt.ts from instance.config.yaml + system-prompt.vN.template.md, do not edit manually -->`
3. **`--check` モード**: 既存 file と diff、差分があれば exit 1。pre-commit hook や CI で「config いじったのに rebuild 忘れ」を catch
4. **失敗時の挙動**: 未定義の placeholder (例: テンプレが `{{org.full_name}}` を要求するが config に無い) は **build を fail** (Mustache の strict mode 相当)。silent な空文字置換は禁止
5. **複数 version の併存**: `vN.template.md` を複数併存させてビルド可能にする CLI 設計

#### Mustache だけだと表現できない部分の扱い

- **`{{domains_length}}`**: Mustache に `length` ヘルパーは無いため、`build-prompt.ts` 側で config を読む直後に `domains_length` をトップレベルに注入してから render (薄いプリプロセス層を許容)
- **末尾カンマ問題**: `{{#primary_repos}}{{.}}, {{/primary_repos}}` → 末尾に余計なカンマが残る。日本語 SP では実害が小さいので許容

#### CI / pre-commit 統合 (最小)

- pre-commit (任意): `bun run scripts/build-prompt.ts --check`
- CI: 同上 + `terraform validate` + `bun run scripts/lint-domain-enum.ts`

---

## 4. Terraform integration

### 4.1 Locals 構造化

`infra/terraform/main.tf` で `instance.config.yaml` を `yamldecode` で読み、すべての resource はこの local 経由で値を参照する:

```hcl
locals {
  config = yamldecode(file("${path.module}/../../instance.config.yaml"))

  prefix     = local.config.infra.prefix
  worker_url = "${local.prefix}.${local.config.infra.workers_dev_subdomain}.workers.dev"

  names = {
    r2_bucket           = "${local.prefix}-corpus"
    ai_search_instance  = "${local.prefix}-instance"
    ai_gateway          = "${local.prefix}-gw"
    worker_script       = local.prefix
    service_token       = "${local.prefix}-mcp"
    otp_idp             = "OTP @${local.config.infra.otp_email_domain}"
    access_app_chat     = "${local.prefix}-chat"
    access_app_mcp      = "${local.prefix}-mcp"
    access_app_catchall = "${local.prefix}-catchall"
  }
}
```

### 4.2 `terraform.tfvars.example` の最終形

**Secrets only**。config 系の override は YAML 経由のみ:

```hcl
# infra/terraform/.env (gitignored)
TF_VAR_cloudflare_api_token=<your-token>
TF_VAR_cloudflare_api_token_id=<your-token-uuid>
```

config 系の override を tfvars でも許容すると 2 重管理 + どちらが勝つかの混乱が発生するため、**意図的に許容しない**。

---

## 5. Clone 手順 (新 instance を立ち上げる)

`README.md` 「このリポジトリを別 instance のテンプレートとして使う」§ を参照。要点:

1. 本テンプレを clone
2. `cp instance.config.example.yaml instance.config.yaml` して値を書き換え
3. `corpus/` 配下を新 instance のドキュメントで差し替え
4. `bun install && bun run scripts/build-prompt.ts --version v2.1` で SP を再生成
5. `cd infra/terraform && cp .env.example .env` して token を設定
6. `just bootstrap` (= build-prompt + terraform init + plan + apply)
7. `just sync-secrets` で Worker secret + root .env を sync
8. `cd ../../worker && wrangler deploy`
9. corpus を R2 に sync (infra/terraform/README.md §7 参照)

---

## 6. docs の扱い (L5: 自動化なし、手動運用ルール)

新 instance では以下のパターンで運用することを **推奨** (強制ルールではない):

- `docs/decisions/0001` `0002` は **framework decisions** として残す (terraform 採用 / テンプレ化方針)
- `docs/decisions/0003+` は **instance 固有 decisions** として書く (新 instance の判断記録)
- `docs/context/` の framework 共通部 (例: phase-plan / setup-qa) は適宜 redact / 置換
- corpus の機微情報サニタイズは `corpus/README.md` の規約に従う

---

## 7. 用語

| 語 | 意味 |
|---|---|
| L1〜L6 | 変数化対象の層番号。L1=インフラ命名 / L2=SP 組織固有部 / L3=corpus 分類軸 / L4=eval / L5=docs (今回 non-goal) / L6=UI 文字列 |
| 案 A / B / C | 採用方針の検討候補。本 spec は案 A を採用 |
| instance | 本テンプレを clone して立てる 1 つの稼働実体 |
