"""What every AfriCinemas MCP App card shares (P8.3): its base look and its bridge to the host.

A card is one self-contained HTML page (`page`) that a host (Claude) shows in a sandboxed
frame and talks to with postMessage, as MCP Apps 2026-01-26 sets out. The bridge here:

- asks ui/initialize (again, backing off from 0.4 s to 5 s, for 30 s) until the host
  answers, then says ui/notifications/initialized;
- hands the tool's input and result to the card (`onToolInput`, `onToolResult`, which
  each card defines), answers ui/resource-teardown, and refuses other requests;
- follows the host's theme and style variables, and wears the cinema's accent colours
  when they're plain hex colours (`useBrand`);
- tells the host its height after every change (ui/notifications/size-changed);
- opens links through the host (ui/open-link), asks the chat for things (ui/message)
  and calls the server's tools (tools/call).

Nothing loads from outside, and text from a cinema is only ever set as text
(textContent), never parsed as HTML.
"""

glob BASE_CSS: str = """:root {
  color-scheme: light dark;
  --bg: var(--color-background-primary, #ffffff);
  --fg: var(--color-text-primary, #1c1b22);
  --muted: var(--color-text-secondary, #5b5966);
  --line: var(--color-border-primary, #e3e1ea);
  --soft: var(--color-background-secondary, #f4f3f8);
  --accent: #3F35C4;
  --on-accent: #ffffff;
  --radius: var(--border-radius-md, 10px);
  font-family: var(--font-sans, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif);
}
:root[data-theme="dark"] {
  --bg: var(--color-background-primary, #17161c);
  --fg: var(--color-text-primary, #f2f1f6);
  --muted: var(--color-text-secondary, #a9a6b6);
  --line: var(--color-border-primary, #2c2a35);
  --soft: var(--color-background-secondary, #22212a);
  --accent: #B8892A;
  --on-accent: #17161c;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--bg); color: var(--fg); }
body { font-size: 15px; line-height: 1.5; }
main { padding: 16px; }
.status { margin: 0; color: var(--muted); }
button { font: inherit; font-weight: 600; min-height: 44px; padding: 0 16px; border-radius: var(--radius); cursor: pointer; border: 1px solid var(--line); background: var(--soft); color: var(--fg); }
button.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
""",
     BRIDGE_JS: str = """  var host = window.parent;
  var card = document.getElementById("card");
  var nextId = 1;
  var waiting = {};
  var ready = false;

  function send(message) { host.postMessage(message, "*"); }
  function notify(method, params) { send({ jsonrpc: "2.0", method: method, params: params || {} }); }
  function request(method, params) {
    var id = nextId++;
    send({ jsonrpc: "2.0", id: id, method: method, params: params || {} });
    return new Promise(function (resolve, reject) { waiting[id] = { resolve: resolve, reject: reject }; });
  }

  // Height, after every change: the host sizes the frame to it.
  var sizeQueued = false;
  function reportSize() {
    if (sizeQueued) { return; }
    sizeQueued = true;
    window.requestAnimationFrame(function () {
      sizeQueued = false;
      var box = document.documentElement;
      notify("ui/notifications/size-changed", { width: box.scrollWidth, height: box.scrollHeight });
    });
  }
  if (window.ResizeObserver) { new ResizeObserver(reportSize).observe(document.body); }

  // The cinema's accent colours, light and dark: plain hex colours only.
  var brand = null;
  function isHex(value) { return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value); }
  function applyBrand() {
    var mode = document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
    var colours = brand && brand[mode];
    var root = document.documentElement.style;
    if (colours && isHex(colours.accent) && isHex(colours.on_accent)) {
      root.setProperty("--accent", colours.accent);
      root.setProperty("--on-accent", colours.on_accent);
    } else {
      root.removeProperty("--accent");
      root.removeProperty("--on-accent");
    }
  }
  function useBrand(colours) {
    brand = colours && typeof colours === "object" ? colours : null;
    applyBrand();
  }

  function applyContext(context) {
    if (!context) { return; }
    if (context.theme === "dark" || context.theme === "light") {
      document.documentElement.setAttribute("data-theme", context.theme);
      applyBrand();
    }
    var vars = context.styles && context.styles.variables;
    if (vars && typeof vars === "object") {
      Object.keys(vars).forEach(function (name) {
        if (name.indexOf("--") === 0 && typeof vars[name] === "string") {
          document.documentElement.style.setProperty(name, vars[name]);
        }
      });
    }
  }

  function isWebLink(url) {
    return typeof url === "string" && (url.indexOf("https:") === 0 || url.indexOf("http:") === 0);
  }
  function openLink(url) {
    if (isWebLink(url)) { request("ui/open-link", { url: url }).catch(function () {}); }
  }
  // Asks the chat for something, as if the customer had typed it.
  function say(text) {
    request("ui/message", { role: "user", content: [{ type: "text", text: text }] }).catch(function () {});
  }
  function callTool(name, args) {
    return request("tools/call", { name: name, arguments: args || {} });
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }
  function button(label, primary, onClick) {
    var node = el("button", primary ? "primary" : "", label);
    node.type = "button";
    node.addEventListener("click", onClick);
    return node;
  }
  function show(nodes) {
    card.textContent = "";
    nodes.forEach(function (node) { card.appendChild(node); });
    reportSize();
  }
  function message(text) { show([el("p", "status", text)]); }
  function resultText(result, otherwise) {
    var said = ((result && result.content) || []).filter(function (c) { return c && c.type === "text"; });
    return said.length > 0 ? said[0].text : otherwise;
  }
  function dayName(starts) {
    // "2026-10-11 18:15" is the cinema's local time: read its parts, not a time zone.
    var parts = String(starts).slice(0, 10).split("-");
    var day = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    if (isNaN(day.getTime())) { return String(starts).slice(0, 10); }
    return day.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
  }

  window.addEventListener("message", function (event) {
    if (event.source !== host) { return; }
    var msg = event.data;
    if (!msg || msg.jsonrpc !== "2.0") { return; }
    if (msg.method === undefined) {
      var pending = waiting[msg.id];
      if (!pending) { return; }
      delete waiting[msg.id];
      if (msg.error) { pending.reject(msg.error); } else { pending.resolve(msg.result); }
      return;
    }
    var params = msg.params || {};
    if (msg.method === "ui/notifications/tool-input") {
      onToolInput(params.arguments || {});
    } else if (msg.method === "ui/notifications/tool-result") {
      if (params) { onToolResult(params); }
    } else if (msg.method === "ui/notifications/tool-cancelled") {
      message("Cancelled.");
    } else if (msg.method === "ui/notifications/host-context-changed") {
      applyContext(params);
    } else if (msg.method === "ui/resource-teardown") {
      send({ jsonrpc: "2.0", id: msg.id, result: {} });
    } else if (msg.id !== undefined) {
      send({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "Method not found" } });
    }
  });

  // The handshake: ask until the host answers, backing off from 0.4 s to 5 s, for 30 s.
  function initialized(result) {
    if (ready) { return; }
    ready = true;
    applyContext(result && result.hostContext);
    notify("ui/notifications/initialized", {});
    reportSize();
  }
  var delay = 400;
  var waited = 0;
  function initialize() {
    if (ready) { return; }
    request("ui/initialize", {
      appInfo: { name: appName, version: "0.8.3" },
      appCapabilities: { availableDisplayModes: ["inline"] },
      protocolVersion: "2026-01-26"
    }).then(initialized, function () {});
    if (waited < 30000) {
      window.setTimeout(initialize, delay);
      waited += delay;
      delay = Math.min(delay * 2, 5000);
    }
  }
""";

def page(title: str, loading: str, css: str, script: str) -> str {
    # A card's whole page: the shared look and bridge around its own styles and script,
    # which must set `appName` and define onToolInput(args) and onToolResult(result).
    return "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        + "<title>"
        + title
        + "</title>\n<style>\n"
        + BASE_CSS
        + css
        + "</style>\n</head>\n<body>\n<main id=\"card\" aria-live=\"polite\"><p class=\"status\">"
        + loading
        + "</p></main>\n<script>\n(function () {\n  \"use strict\";\n"
        + BRIDGE_JS
        + script
        + "\n  initialize();\n}());\n</script>\n</body>\n</html>\n";
}
