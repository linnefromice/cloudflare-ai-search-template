// AI Search への 2 系統 proxy + chat UI 配信。
//
// 1. GET /                            → AI Search Snippets <chat-page-snippet> embed HTML
// 2. POST /chat/completions, /search  → REST API (Bearer auth) で AI Search instance を直叩き
//                                       (Public Endpoint の anti-abuse rate limit を回避)
// 3. POST /mcp                        → Public Endpoint pass-through (REST API 経路が公式に存在しない)
// 4. その他 (例: /assets/...)           → Public Endpoint pass-through (Snippets script 等の取得用)
//
// rate limit 構造の補足:
// - Public Endpoint <UUID>.search.ai.cloudflare.com は anti-abuse 用の厳しい rate bucket
// - REST API api.cloudflare.com/client/v4/.../ai-search/instances/{NAME}/... は通常の API quota
// - Gemini Free Tier は 15 RPM / 1500 RPD で別レイヤの制約 (eval script 側で sleep 必須)

interface Env {
  AI_SEARCH_INSTANCE: string;        // UUID, Public Endpoint hostname 用
  AI_SEARCH_INSTANCE_NAME: string;   // human-readable name, REST API path 用
  AI_SEARCH_ACCOUNT_ID: string;      // Cloudflare Account ID, REST API path 用
  AI_SEARCH_API_TOKEN: string;       // secret, scope: AI Search:Edit + AI Search:Run
  PAGE_TITLE: string;                // UI title (wrangler.toml [vars])
}

const SNIPPET_ASSET_VERSION = "v0.0.38";

const REST_API_PATHS = new Set(["/chat/completions", "/search"]);

const chatPageHtml = (instance: string, pageTitle: string): string => `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${pageTitle}</title>
  <style>
    html, body { margin: 0; padding: 0; height: 100%; }
    body { font-family: system-ui, -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif; }
    chat-page-snippet { display: block; height: 100vh; }
  </style>
</head>
<body>
  <chat-page-snippet api-url="/" theme="auto"></chat-page-snippet>
  <script>
    // IME 変換確定の Enter で送信されるのを抑止する patch.
    // Snippet (chat-page-snippet) が \`event.isComposing\` を見ずに keydown Enter で submit するため、
    // document の capture phase で先取りして IME 中の Enter は stopPropagation する。
    // Snippet の通常の Enter 送信は IME 非アクティブ時のみ通す。preventDefault はせず IME 確定動作は維持。
    (function() {
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && (e.isComposing || e.keyCode === 229)) {
          e.stopPropagation();
        }
      }, true);
    })();
  </script>
  <script type="module" src="https://${instance}.search.ai.cloudflare.com/assets/${SNIPPET_ASSET_VERSION}/search-snippet.es.js"></script>
</body>
</html>`;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const incoming = new URL(request.url);

    // 1. chat UI HTML
    if (incoming.pathname === "/" && request.method === "GET") {
      return new Response(chatPageHtml(env.AI_SEARCH_INSTANCE, env.PAGE_TITLE), {
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
        },
      });
    }

    // 2. /chat/completions と /search は REST API (Bearer auth) 経由で叩く
    if (REST_API_PATHS.has(incoming.pathname) && request.method === "POST") {
      const restUrl =
        `https://api.cloudflare.com/client/v4/accounts/${env.AI_SEARCH_ACCOUNT_ID}` +
        `/ai-search/instances/${env.AI_SEARCH_INSTANCE_NAME}` +
        incoming.pathname +
        incoming.search;

      const restHeaders = new Headers();
      restHeaders.set("Authorization", `Bearer ${env.AI_SEARCH_API_TOKEN}`);
      restHeaders.set("Content-Type", "application/json");
      const accept = request.headers.get("Accept");
      if (accept) restHeaders.set("Accept", accept);

      return fetch(restUrl, {
        method: "POST",
        headers: restHeaders,
        body: request.body,
      });
    }

    // 3 & 4. /mcp や /assets/... 等は Public Endpoint pass-through
    const upstream = new URL(
      incoming.pathname + incoming.search,
      `https://${env.AI_SEARCH_INSTANCE}.search.ai.cloudflare.com`
    );

    const headers = new Headers(request.headers);
    headers.set("Host", upstream.host);

    return fetch(upstream.toString(), {
      method: request.method,
      headers,
      body: request.body,
    });
  },
};
