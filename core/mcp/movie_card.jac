"""The movie card (P8.2): the MCP App that core/mcp/server.jac serves as ui://africinemas/movie-card.

A host (Claude) shows it in a sandboxed frame and talks to it with postMessage, as MCP
Apps 2026-01-26 sets out: the card asks ui/initialize (again, backing off, until the host
answers), says ui/notifications/initialized, then draws show_movie's result when the host
sends ui/notifications/tool-result. It tells the host its height after every change.

Self-contained: no outside scripts, styles, fonts or images (the poster comes as a data
URL). The movie's text is the cinema's, so it's only ever set as text (textContent),
never parsed as HTML. Links (the trailer page, booking) open through the host
(ui/open-link); the trailer plays in a frame only from the two players the CSP allows.

It's kept as a string here, not an .html file, so it ships wherever the Jac code does.
"""

glob CARD_HTML: str = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Movie</title>
<style>
:root {
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
.top { display: flex; gap: 16px; align-items: flex-start; }
.poster { width: 112px; aspect-ratio: 2 / 3; border-radius: var(--radius); object-fit: cover; flex: none; background: var(--soft); }
.info { min-width: 0; flex: 1; }
h1 { font-size: 20px; line-height: 1.25; margin: 0 0 4px; overflow-wrap: anywhere; }
.facts, .where { margin: 0; color: var(--muted); }
.actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
button { font: inherit; font-weight: 600; min-height: 44px; padding: 0 16px; border-radius: var(--radius); cursor: pointer; border: 1px solid var(--line); background: var(--soft); color: var(--fg); }
button.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.player { margin-top: 16px; position: relative; aspect-ratio: 16 / 9; border-radius: var(--radius); overflow: hidden; background: #000; }
.player iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
.synopsis { margin: 16px 0 0; display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }
h2 { font-size: 15px; margin: 16px 0 8px; }
.day { margin: 0 0 8px; }
.day-name { margin: 0 0 4px; font-weight: 600; font-size: 14px; }
.times { display: flex; flex-wrap: wrap; gap: 6px; margin: 0; padding: 0; list-style: none; }
.times li { padding: 4px 10px; border-radius: 999px; background: var(--soft); border: 1px solid var(--line); font-size: 14px; font-variant-numeric: tabular-nums; }
.times .place { color: var(--muted); }
@media (max-width: 380px) {
  .top { flex-direction: column; }
  .poster { width: 96px; }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
</style>
</head>
<body>
<main id="card" aria-live="polite"><p class="status">Loading the movie…</p></main>
<script>
(function () {
  "use strict";
  var host = window.parent;
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

  function applyContext(context) {
    if (!context) { return; }
    if (context.theme === "dark" || context.theme === "light") {
      document.documentElement.setAttribute("data-theme", context.theme);
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

  function duration(minutes) {
    var m = Number(minutes) || 0;
    if (m <= 0) { return ""; }
    var h = Math.floor(m / 60);
    return h > 0 ? h + " h " + (m % 60) + " min" : m + " min";
  }
  function dayName(starts) {
    // "2026-10-11 18:15" is the cinema's local time: read its parts, not a time zone.
    var parts = String(starts).slice(0, 10).split("-");
    var day = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    if (isNaN(day.getTime())) { return String(starts).slice(0, 10); }
    return day.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
  }

  var trailerAllowed = ["https://www.youtube-nocookie.com/embed/", "https://player.vimeo.com/video/"];
  function playTrailer(holder, embed) {
    var allowed = trailerAllowed.some(function (prefix) { return embed.indexOf(prefix) === 0; });
    if (!allowed || holder.firstChild) { return; }
    var frame = document.createElement("iframe");
    frame.src = embed + "?autoplay=1";
    frame.title = "Trailer";
    frame.allow = "autoplay; encrypted-media; picture-in-picture; fullscreen";
    frame.setAttribute("allowfullscreen", "");
    frame.referrerPolicy = "strict-origin-when-cross-origin";
    holder.appendChild(frame);
    holder.hidden = false;
    reportSize();
  }

  function showMovie(movie, poster) {
    var top = el("div", "top");
    if (typeof poster === "string" && poster.indexOf("data:image/") === 0) {
      var image = el("img", "poster");
      image.alt = "Poster for " + movie.title;
      image.src = poster;
      image.addEventListener("load", reportSize);
      top.appendChild(image);
    }
    var info = el("div", "info");
    info.appendChild(el("h1", "", movie.title));
    var facts = [movie.age_rating, duration(movie.runtime_minutes)]
      .concat(Array.isArray(movie.genres) ? movie.genres : [])
      .concat([movie.language])
      .filter(function (fact) { return fact; });
    if (facts.length > 0) { info.appendChild(el("p", "facts", facts.join(" · "))); }
    info.appendChild(el("p", "where", movie.cinema));

    var player = el("div", "player");
    player.hidden = true;
    var actions = el("div", "actions");
    if (movie.trailer_embed) {
      actions.appendChild(button("Play trailer", true, function () { playTrailer(player, movie.trailer_embed); }));
    }
    if (movie.trailer_url) {
      actions.appendChild(button("Trailer on the web", false, function () { openLink(movie.trailer_url); }));
    }
    if (movie.book_url) {
      actions.appendChild(button("Book tickets", !movie.trailer_embed, function () { openLink(movie.book_url); }));
    }
    info.appendChild(actions);
    top.appendChild(info);

    var nodes = [top, player];
    if (movie.synopsis) { nodes.push(el("p", "synopsis", movie.synopsis)); }
    var times = Array.isArray(movie.showtimes) ? movie.showtimes : [];
    nodes.push(el("h2", "", times.length > 0 ? "Showtimes" : "No showtimes on sale"));
    var days = {};
    var order = [];
    times.forEach(function (s) {
      var key = String(s.starts).slice(0, 10);
      if (!days[key]) { days[key] = []; order.push(key); }
      days[key].push(s);
    });
    order.forEach(function (key) {
      var group = el("section", "day");
      group.appendChild(el("p", "day-name", dayName(days[key][0].starts)));
      var list = el("ul", "times");
      days[key].forEach(function (s) {
        var item = el("li", "", String(s.starts).slice(11, 16) + " ");
        item.appendChild(el("span", "place", [s.venue, s.screen].filter(function (p) { return p; }).join(", ")));
        list.appendChild(item);
      });
      group.appendChild(list);
      nodes.push(group);
    });
    show(nodes);
  }

  function showResult(result) {
    if (!result) { return; }
    var said = (result.content || []).filter(function (c) { return c && c.type === "text"; });
    if (result.isError || !result.structuredContent) {
      message(said.length > 0 ? said[0].text : "This movie couldn't be shown.");
      return;
    }
    var meta = result._meta || {};
    showMovie(result.structuredContent, meta["africinemas/poster"]);
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
      var asked = params.arguments && params.arguments.movie;
      message(asked ? "Finding " + asked + "…" : "Loading the movie…");
    } else if (msg.method === "ui/notifications/tool-result") {
      showResult(params);
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
      appInfo: { name: "africinemas-movie-card", version: "0.8.2" },
      appCapabilities: { availableDisplayModes: ["inline"] },
      protocolVersion: "2026-01-26"
    }).then(initialized, function () {});
    if (waited < 30000) {
      window.setTimeout(initialize, delay);
      waited += delay;
      delay = Math.min(delay * 2, 5000);
    }
  }
  initialize();
}());
</script>
</body>
</html>
""";
