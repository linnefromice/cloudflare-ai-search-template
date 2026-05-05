import { describe, expect, test } from "bun:test";
import { renderStrict, parseArgs } from "./build-prompt";

describe("renderStrict", () => {
  test("renders a simple variable", () => {
    const result = renderStrict("Hello {{name}}", { name: "World" });
    expect(result).toBe("Hello World");
  });

  test("renders nested object access", () => {
    const result = renderStrict("Org: {{org.name}}", { org: { name: "Acme" } });
    expect(result).toBe("Org: Acme");
  });

  test("renders a section over an array", () => {
    const result = renderStrict(
      "{{#items}}{{.}},{{/items}}",
      { items: ["a", "b", "c"] }
    );
    expect(result).toBe("a,b,c,");
  });

  test("throws when a referenced variable is missing", () => {
    expect(() =>
      renderStrict("Hello {{missing}}", {})
    ).toThrow(/missing/);
  });

  test("throws when a nested path is incomplete", () => {
    expect(() =>
      renderStrict("Org: {{org.name}}", { org: {} })
    ).toThrow(/org.name/);
  });

  test("does not throw when an inverted section's key is missing (default render)", () => {
    // {{^missing}}...{{/missing}} should render the inner content when 'missing' is absent
    const result = renderStrict("{{^missing}}fallback{{/missing}}", {});
    expect(result).toBe("fallback");
  });

  test("HTML-escapes {{var}} by default (Mustache standard behavior)", () => {
    // Mustache's default escape behavior — useful as a regression test
    // to make any future change of this default loud.
    const result = renderStrict("Path: {{p}}", { p: "a/b" });
    expect(result).toBe("Path: a&#x2F;b");
  });

  test("does NOT escape {{&var}} (used for paths and other non-HTML content)", () => {
    const result = renderStrict("Path: {{&p}}", { p: "a/b" });
    expect(result).toBe("Path: a/b");
  });
});

import { parseArgs } from "./build-prompt";

describe("parseArgs", () => {
  test("--version v2 --check parses both flags correctly", () => {
    expect(parseArgs(["--version", "v2", "--check"])).toEqual({ version: "v2", check: true });
  });

  test("--check --version v2 parses both flags correctly", () => {
    expect(parseArgs(["--check", "--version", "v2"])).toEqual({ version: "v2", check: true });
  });

  test("--version followed by another flag does not consume the flag", () => {
    // --version --check should treat --check as a flag, leaving version at default
    const result = parseArgs(["--version", "--check"]);
    expect(result.check).toBe(true);
    expect(result.version).not.toBe("--check");
  });

  test("defaults to v2.1 with no args", () => {
    expect(parseArgs([])).toEqual({ version: "v2.1", check: false });
  });
});
