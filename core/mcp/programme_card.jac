"""The programme card (P8.3): the MCP App that core/mcp/server.jac serves as ui://africinemas/whats-on.

whats_on's result fills it: the cinema's showtimes on sale, day by day, each day a row of
poster tiles with that day's times. The posters come one at a time from movie_poster (a
tool only the cards may call), so the result itself carries no images. Tapping a movie
asks the chat to show it (ui/message), which draws its movie card; "Book on the website"
opens the cinema's storefront (ui/open-link). The shared look and the host bridge come
from card_kit.jac.
"""

import from core.mcp.card_kit { page }

glob PROGRAMME_CSS: str = """h1 { font-size: 20px; line-height: 1.25; margin: 0 0 12px; overflow-wrap: anywhere; }
.day { margin: 0 0 16px; }
.day-name { margin: 0 0 8px; font-weight: 600; font-size: 14px; }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(116px, 1fr)); gap: 12px; margin: 0; padding: 0; list-style: none; }
.tile { display: flex; flex-direction: column; align-items: stretch; gap: 6px; width: 100%; min-height: 44px; padding: 0; border: 0; background: none; text-align: left; font-weight: 400; border-radius: var(--radius); }
.art { aspect-ratio: 2 / 3; border-radius: var(--radius); background: var(--soft); border: 1px solid var(--line); overflow: hidden; display: grid; place-items: center; padding: 8px; color: var(--muted); font-size: 13px; text-align: center; }
.art img { width: 100%; height: 100%; object-fit: cover; display: block; }
.art.has-image { padding: 0; }
.name { font-weight: 600; line-height: 1.3; overflow-wrap: anywhere; }
.times { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; }
.footer { margin-top: 4px; }
""",
     PROGRAMME_JS: str = """  var appName = "africinemas-whats-on";
  var posters = {};
  var waitingArt = {};

  function setArt(box, title, poster) {
    box.textContent = "";
    if (typeof poster === "string" && poster.indexOf("data:image/") === 0) {
      var image = el("img");
      image.alt = "";
      image.src = poster;
      box.className = "art has-image";
      box.appendChild(image);
    } else {
      box.className = "art";
      box.textContent = title;
    }
  }

  // Posters one at a time, each once, through the cards' own tool.
  function loadPosters(slug, movies) {
    var queue = movies.slice();
    function next() {
      var movie = queue.shift();
      if (!movie) { return; }
      callTool("movie_poster", { cinema: slug, movie_key: movie.movie_key }).then(function (result) {
        var meta = (result && result._meta) || {};
        posters[movie.movie_key] = meta["africinemas/poster"] || "";
        (waitingArt[movie.movie_key] || []).forEach(function (box) {
          setArt(box, movie.title, posters[movie.movie_key]);
        });
        reportSize();
      }, function () {}).then(next);
    }
    next();
  }

  function tile(programme, movie, times) {
    var item = el("li");
    var choose = button("", false, function () {
      say("Show me " + movie.title + " at " + programme.cinema);
    });
    choose.className = "tile";
    choose.setAttribute("aria-label", "Show " + movie.title + ", " + times.join(", "));
    var art = el("span", "art", movie.title);
    waitingArt[movie.movie_key] = (waitingArt[movie.movie_key] || []).concat([art]);
    if (posters[movie.movie_key] !== undefined) { setArt(art, movie.title, posters[movie.movie_key]); }
    choose.appendChild(art);
    choose.appendChild(el("span", "name", movie.title));
    choose.appendChild(el("span", "times", times.join(" · ")));
    item.appendChild(choose);
    return item;
  }

  function showProgramme(programme) {
    var nodes = [el("h1", "", "What's on at " + programme.cinema)];
    var days = Array.isArray(programme.days) ? programme.days : [];
    var movies = Array.isArray(programme.movies) ? programme.movies : [];
    var titles = {};
    movies.forEach(function (m) { titles[m.movie_key] = m; });
    if (days.length === 0) {
      nodes.push(el("p", "status", "Nothing is on sale right now."));
    }
    days.forEach(function (day) {
      var group = el("section", "day");
      group.appendChild(el("h2", "day-name", dayName(day.day)));
      var list = el("ul", "tiles");
      var order = [];
      var times = {};
      (day.showtimes || []).forEach(function (s) {
        if (!times[s.movie_key]) { times[s.movie_key] = []; order.push(s.movie_key); }
        times[s.movie_key].push(String(s.starts).slice(11, 16));
      });
      order.forEach(function (key) {
        if (titles[key]) { list.appendChild(tile(programme, titles[key], times[key])); }
      });
      group.appendChild(list);
      nodes.push(group);
    });
    if (programme.site_url) {
      var footer = el("div", "footer");
      footer.appendChild(button("Book on the website", true, function () { openLink(programme.site_url); }));
      nodes.push(footer);
    }
    show(nodes);
    loadPosters(programme.cinema_slug, movies);
  }

  function onToolInput(args) {
    message("Loading what's on…");
  }
  function onToolResult(result) {
    if (result.isError || !result.structuredContent) {
      message(resultText(result, "The programme couldn't be shown."));
      return;
    }
    useBrand(result.structuredContent.brand);
    showProgramme(result.structuredContent);
  }
""";

glob PROGRAMME_HTML: str = page(
         "What's on", "Loading what's on…", PROGRAMME_CSS, PROGRAMME_JS
     );
