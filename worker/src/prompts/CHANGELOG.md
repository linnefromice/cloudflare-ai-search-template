# System Prompt CHANGELOG

System Prompt の version 履歴。各 version は `system-prompt.vN.template.md` を template として保持し、`scripts/build-prompt.ts` で `instance.config.yaml` の値と合成して `system-prompt.vN.md` (deploy artifact) を render する。

## v2.1 (current) — 圧縮版、token cost -38% (3500 → ~2200 tokens)

**Source**: v2 を冗長性除去・命令形統一・例示削減で圧縮
**File**: `system-prompt.v2.1.template.md` → `system-prompt.v2.1.md`

### 圧縮戦略

- 命令形に統一 (`～してください` → `～する`)
- 出力構造の単一/横断 template を 1 つに統一、横断時の差分のみ注記
- §6 user context: prefix 数を削減 (`@<repo>` で代替可なものは削除)
- §7 status icon: 7 → 6 (`💡 exploration` を削除、scope の方で表現)
- 各 §の説明文を冗長な部分だけ刈り取り、ルール本文は維持

### 採用判断 (例)

評価メトリクスの target (corpus / eval セットによって調整):

- **GO**: brand-name 警戒ルールが citation-level で機能 (η finding 解消) + Recall@5 が v2 から大きく劣化しない
- **CONDITIONAL**: 一部 target 未達 → 個別ルールの再調整
- **NO-GO**: v2 を全面的に下回る → ロールバック、別アプローチ検討

## v2 — context-aware retrieval (status / domain / override / brand-name 警戒)

**Source design**: 越境引用ルール / context override / brand-name 抑制を SP 側に明示化
**File**: `system-prompt.v2.template.md` → `system-prompt.v2.md`
**Status**: Superseded by v2.1 (圧縮版採用)

### v1 からの追加 (rule 6-7、既存 1-5 は維持)

| ルール | 内容 | 対応する corpus 側メタデータ |
|---|---|---|
| 2. status 認識 | `status` (confirmed/active/draft/superseded/rejected/archived) ごとに引用ポリシーを変える、`/history` prefix で過去文書も対象に | frontmatter `status` + `reliability` |
| 3. domain 認識 | product / ops / research の domain mapping、`repo` 別の主題区分 | frontmatter `domain` + `repo` |
| 4. 越境引用ルール | (a) 単一 domain クエリ (b) 横断クエリ grouping (c) 不明瞭クエリ + 絶対 NG パターン (**ブランド名 SEO 警戒** ルールが brand-name spam 対策の本命) | corpus 全般 |
| 5. 出力構造 | 単一 domain は[結論+根拠+関連情報+注釈]、横断は domain ごとに section + domain 間の関係 | — |
| 6. user context モード | `/tech` `/ops` `/research` `/all` `/history` `@<repo>` を最強の制約として扱う | `domain` / `repo` |
| 7. citation 表記 | `📄 <path> [<icon> <status> × <scope>] (as_of: ...) GitHub: <url>` の固定フォーマット | frontmatter `as_of` / `original_url` |

### Known issues / pending

- **本テンプレ採用 corpus に superseded / rejected / archived / draft / exploration scope の文書がない場合**: status 認識ルール (rule 2) の effect は negative pattern (該当情報なしと正しく答える) でしか検証できない。corpus 拡大時に positive pattern も加わる
- **citation format compliance metric (rule 7)**: response 全文パースが必要で実装コスト高。eval では Recall@5 + domain_precision + cross_domain_leakage + context_override_respect の 4 メトリクスで近似する想定

## v1.1 — citation example aligned to path-based corpus

**File**: `system-prompt.v1.md` (in-place revision、新ファイル化はせず v1 系の patch として扱う)
**Diff**: rule 3 の citation 例を採番形式 (`0001-example.md`) → path-based 形式 (`product/example/docs/...md`) に書換

**Reason**: corpus を path-based migration した後、citation 例も同形式に揃えることで LLM が citation 形式に迷うリスクを抑制。

## v1 — initial 5-rule structure

**File**: `system-prompt.v1.md`
**Status**: Superseded by v2 (context-aware retrieval が必要なため)

### Initial 5-rule structure

1. 言語固定 — 回答言語の揺らぎ対策 (英語識別子比率で揺れる現象)
2. 構造化レスポンス — 概要 → 詳細 → 補足
3. Citation id 明記 — `item.key` の filename 部分を末尾に
4. 質問の難度に応じた詳細度 — 一問一答を抑制
5. 推測抑制 — 不明時は「該当情報なし」を明示

### Known issues (v2 で解消)

- **brand-name spam 未対処**: ブランド名の SEO description が retrieval top に張り付く現象。SP 側での mitigation (例: 「ブランド名 SEO description は context として軽視」) は v2 で導入
- **status / scope / domain 認識**: 3 軸 frontmatter は corpus 側に投入されるが、v1 SP は status awareness / cross-domain leakage 対策を含まない
