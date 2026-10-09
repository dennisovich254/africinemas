"""The movie card (P8.2): the MCP App that core/mcp/server.jac serves as ui://africinemas/movie-card.

show_movie's result fills it: the poster (in the result's _meta, a data URL), the
movie's details, Play trailer, Book tickets and the showtimes by day. The shared look and
the host bridge come from card_kit.jac.

The trailer plays in a frame only from the two players the CSP allows, with a "Not
playing?" link under it, because some chats block outside players (P8.3: in Claude the
frame stayed black). Links open through the host (ui/open-link).
"""

import from core.mcp.card_kit { page }

glob MOVIE_CSS: str = """.top { display: flex; gap: 16px; align-items: flex-start; }
.poster { width: 112px; aspect-ratio: 2 / 3; border-radius: var(--radius); object-fit: cover; flex: none; background: var(--soft); }
.info { min-width: 0; flex: 1; }
h1 { font-size: 20px; line-height: 1.25; margin: 0 0 4px; overflow-wrap: anywhere; }
.facts, .where { margin: 0; color: var(--muted); }
.actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
.player { margin-top: 16px; position: relative; aspect-ratio: 16 / 9; border-radius: var(--radius); overflow: hidden; background: #000; }
.player iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
.fallback { margin: 8px 0 0; color: var(--muted); font-size: 14px; }
.fallback button { min-height: 44px; padding: 0 8px; border: 0; background: none; color: var(--fg); text-decoration: underline; font-weight: 600; }
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

  var trailerAllowed = ["https://www.youtube-nocookie.com/embed/", "https://player.vimeo.com/video/"];
  function siteName(url) {
    return String(url).indexOf("vimeo") >= 0 ? "Vimeo" : "YouTube";
  }
  function playTrailer(holder, embed, link) {
    var allowed = trailerAllowed.some(function (prefix) { return embed.indexOf(prefix) === 0; });
    if (!allowed || holder.firstChild) { return; }
    // Some chats don't let a card play an outside video: the way out is always there.
    if (link) {
      var way = el("p", "fallback", "Not playing? ");
      way.appendChild(button("Watch on " + siteName(link), false, function () { openLink(link); }));
      holder.parentNode.insertBefore(way, holder.nextSibling);
    }
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
      actions.appendChild(button("Play trailer", true, function () { playTrailer(player, movie.trailer_embed, movie.trailer_url); }));
    } else if (movie.trailer_url) {
      actions.appendChild(button("Watch the trailer", false, function () { openLink(movie.trailer_url); }));
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
