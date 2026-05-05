// corpus/README.md の <domain> enum と instance.config.yaml の domains[].id の同期を check。
// spec ADR 0002 §3.4 #1 (domains を構造化 list にした理由) の手動同期 follow-up。
//
// Usage: bun run scripts/lint-domain-enum.ts
// Exit: 0 = 一致、1 = 不一致 (diff 出力)

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse as parseYaml } from "yaml";

const ROOT = resolve(import.meta.dir, "..");
const CONFIG_PATH = resolve(ROOT, "instance.config.yaml");
const README_PATH = resolve(ROOT, "corpus/README.md");

const config = parseYaml(readFileSync(CONFIG_PATH, "utf8")) as { domains: { id: string }[] };
const yamlDomains = (config.domains ?? []).map((d) => d.id).sort();

// corpus/README.md から `- `<domain>`: `product` / `ops` / `research`` 行を抽出
const readme = readFileSync(README_PATH, "utf8");
const enumMatch = readme.match(/^- `<domain>`:\s*([^\n]+)/m);
if (!enumMatch) {
  console.error(`ERROR: corpus/README.md に \`<domain>\` の enum 行が見つからない`);
  process.exit(1);
}

// 行から `product` / `ops` / `research` を抽出 (`backtick` で囲まれた英数字)
const readmeDomains = [...enumMatch[1].matchAll(/`([a-z][a-z0-9_-]*)`/g)].map((m) => m[1]).sort();

if (JSON.stringify(yamlDomains) !== JSON.stringify(readmeDomains)) {
  console.error(`ERROR: domain enum 不一致`);
  console.error(`  instance.config.yaml domains[].id: ${JSON.stringify(yamlDomains)}`);
  console.error(`  corpus/README.md          <domain>: ${JSON.stringify(readmeDomains)}`);
  console.error(`修正: 片方を更新して両方一致させる (yaml が SoT、README は documentation)`);
  process.exit(1);
}

console.log(`ok: domain enum 一致 (${yamlDomains.join(", ")})`);
