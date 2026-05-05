# scripts/ — Build & utility scripts

Cloudflare AI Search PoC の補助 scripts。

## build-prompt.ts — System Prompt template renderer

`worker/src/prompts/system-prompt.<version>.template.md` を Mustache template として `instance.config.yaml` の値と合成し、`system-prompt.<version>.md` を render する。

terraform は render 結果の `.md` ファイルを `cloudflare_ai_search_instance.system_prompt_aisearch` で deploy するため、`terraform apply` の前に必ず実行する (= `just bootstrap` の中で自動化済)。

### Usage

```bash
# Render latest version (default v2.1)
bun run scripts/build-prompt.ts

# Specific version
bun run scripts/build-prompt.ts --version v2
bun run scripts/build-prompt.ts --version v2.1

# CI-friendly check mode: drift detection (失敗時 exit 1)
# generated と template + config が乖離していたらエラー終了
bun run scripts/build-prompt.ts --check
```

### Mustache 変数

template 内で参照される値は `instance.config.yaml` の以下:

| Mustache | 内容 |
|---|---|
| `{{org.short_name}}` | 組織短縮名 (例: `MyOrg`) |
| `{{org.name}}` | 組織正式名 |
| `{{domains_length}}` | domains 配列長 (auto-injected) |
| `{{#domains}}{{id}}{{label}}{{primary_repos}}{{/domains}}` | domain 配列 iteration |
| `{{#sp_extras.brand_names_to_deprioritize}}{{.}}{{/}}` | brand-name 警戒対象 (空配列でも OK) |
| `{{#sp_extras.noisy_path_examples}}{{&.}}{{/}}` | noisy path 例示 (空配列でも OK) |

template が要求する変数が config に無い場合、`renderStrict` が事前検証で throw する (defensive coding)。

## lint-domain-enum.ts — domain enum 整合性チェック

`instance.config.yaml` の `domains[].id` と corpus 内 frontmatter の `domain:` が整合しているか lint する。

```bash
bun run scripts/lint-domain-enum.ts
```

corpus 拡大時 / 新 domain 追加時に CI で走らせる想定。

## build-prompt.test.ts — unit test

```bash
bun test scripts/build-prompt.test.ts
```

主に `renderStrict` の missing variable 検出と `parseArgs` の挙動検証。

## eval scripts (this template には含めない)

retrieval 品質計測 (Recall@5 / chunk coverage / domain precision 等) を行う eval scripts は instance 固有 (corpus + 質問セット依存) のため、本 template には含めていない。

eval を実装する場合は以下を新規追加する想定:

- `scripts/eval.ts` — `docs/context/eval/questions.yaml` を読んで AI Search `/chat/completions` を順次叩き、メトリクスを集計
- `docs/context/eval/questions.yaml` — 評価用質問セット (期待される citation source / forbidden source 等を annotated で記述)
- `docs/eval/results/` — 結果出力先 (label ごとに json + md)

reference 実装は upstream private repo (本 template の母体) を参照。
