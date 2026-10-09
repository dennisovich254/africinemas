"""The movie card (P8.2): the MCP App that core/mcp/server.jac serves as ui://africinemas/movie-card.

show_movie's result fills it: the poster (in the result's _meta, a data URL), the
movie's details, Watch trailer, Book tickets and the showtimes by day. The shared look
and the host bridge come from card_kit.jac.

Watch trailer opens the trailer's own page through the host (ui/open-link). The card
embeds no player: claude.ai ignores MCP Apps' frameDomains, so an embedded YouTube
player stayed black (P8.3, anthropics/claude-code#59351). Self-hosted trailers, played
by the card itself, can come with object storage.
"""

import from core.mcp.card_kit { page }

glob MOVIE_CSS: str = """.top { display: flex; gap: 16px; align-items: flex-start; }
.poster { width: 112px; aspect-ratio: 2 / 3; border-radius: var(--radius); object-fit: cover; flex: none; background: var(--soft); }
.info { min-width: 0; flex: 1; }
h1 { font-size: 20px; line-height: 1.25; margin: 0 0 4px; overflow-wrap: anywhere; }
.facts, .where { margin: 0; color: var(--muted); }
.actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
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
""",
     MOVIE_JS: str = """  var appName = "africinemas-movie-card";

  function duration(minutes) {
    var m = Number(minutes) || 0;
    if (m <= 0) { return ""; }
    var h = Math.floor(m / 60);
    return h > 0 ? h + " h " + (m % 60) + " min" : m + " min";
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

    var actions = el("div", "actions");
    if (movie.trailer_url) {
      actions.appendChild(button("Watch trailer", true, function () { openLink(movie.trailer_url); }));
    }
    if (movie.book_url) {
      actions.appendChild(button("Book tickets", !movie.trailer_url, function () { openLink(movie.book_url); }));
    }
    info.appendChild(actions);
    top.appendChild(info);

    var nodes = [top];
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

  function onToolInput(args) {
    message(args.movie ? "Finding " + args.movie + "…" : "Loading the movie…");
  }
  function onToolResult(result) {
    if (result.isError || !result.structuredContent) {
      message(resultText(result, "This movie couldn't be shown."));
      return;
    }
    useBrand(result.structuredContent.brand);
    var meta = result._meta || {};
    showMovie(result.structuredContent, meta["africinemas/poster"]);
  }
""";

glob CARD_HTML: str = page("Movie", "Loading the movie…", MOVIE_CSS, MOVIE_JS);
