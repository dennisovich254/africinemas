"""The storefront the AI wrote (ADR-0048), drawn and filled from the programme.

The template arrives sanitized (core/theming/pagecode.jac). Here it is parsed with the
browser's DOMParser and drawn as React elements: never put into the page as HTML. Only
allowlisted tags and attributes are drawn again, and nothing that runs is (no event
handlers, no src or href but ours). The slots are filled from public_home:
- data-each repeats an element per film or showtime (featured, films, film.times,
  today, soon) and data-empty shows an element only when its list is empty;
- data-text puts our text in, data-img our logo or a poster, data-link our routes;
- data-motif paints the logo's own figure from the brand kit (ADR-0046) in the element's
  CSS colour, through the motif's mask: "single" is the first motif, "group" the last.
  Without a kit the element isn't drawn.

AiPart draws one part (header, home or footer) inside a .ai-page wrapper, the scope of
the template's stylesheet, so the AI's CSS never reaches our own pages (movie,
checkout, tickets) between its header and footer.
"""

import from react { createElement, useState, useEffect }

# createElement for any tag the template names; its typed overloads expect one tag each.
glob make: any = createElement;  # jac:ignore[W1037]
import from "@jac/runtime" { Link }
import from core.catalog.storefront_api { public_poster }
import from .showtimes {
    details_line,
    time_label,
    cinema_today,
    cinema_date,
    date_label,
    release_label
}

glob SVG_NS: str = "http://www.w3.org/2000/svg",
     DROP: list[str] = [
         "script",
         "style",
         "iframe",
         "object",
         "embed",
         "form",
         "input",
         "button",
         "textarea",
         "select",
         "link",
         "meta",
         "base",
         "foreignObject",
         "image",
         "video",
         "audio",
         "canvas",
         "template"
     ],
     # HTML attribute names React spells differently.
     REACT_NAMES: dict[str, str] = {
         "class": "className",
         "tabindex": "tabIndex",
         "datetime": "dateTime",
         "for": "htmlFor"
     };

def:pub kit_masks(kit: dict[str, any] | None) -> list[str] {  # jac:ignore[W1037]
    # The brand kit's motif masks (data URLs), single figure first; [] without a kit.
    if kit is None {
        return [];
    }
    motifs: list[dict[str, str]] = kit["motifs"] or [];
    return [m["mask"] for m in motifs];
}

def:pub ai_page_of(branding: dict[str, any] | None) -> dict[str, str] | None {  # jac:ignore[W1037]
    # The written page, or None. In the browser an empty object is true: test its html.
    if branding is None {
        return None;
    }
    page: dict[str, str] = branding["page"] or {};
    return page if page["html"] else None;
}

def _show(s: dict[str, any], tz: str, today: str, title: str) -> dict[str, any] {  # jac:ignore[W1037]
    screen: str = s["screen"]["name"] if s["screen"] else "";
    return {
        "show.time": time_label(s["starts_at"], tz),
        "show.day": date_label(cinema_date(s["starts_at"], tz), today),
        "show.screen": screen,
        "show.film": title or s["title"] or "",
        "_show": s["screening_id"]
    };
}

def _film(m: dict[str, any], tz: str, today: str) -> dict[str, any] {  # jac:ignore[W1037]
    upcoming: list[dict[str, any]] = m["next"] or [];  # jac:ignore[W1037]
    return {
        "film.title": m["title"],
        "film.details": details_line(m),
        "film.synopsis": m["synopsis"] or "",
        "film.release": release_label(m["release_date"]) if m["release_date"] else "",
        "_film": m["movie_key"],
        "_poster": m["movie_key"] if m["has_poster"] else "",
        "times": [_show(s, tz, today, m["title"]) for s in upcoming]
    };
}

def:pub ai_lists(home: dict[str, any] | None) -> dict[str, any] {  # jac:ignore[W1037]
    # The template's lists from public_home: featured, films, today, soon.
    lists: dict[str, any] = {"featured": [], "films": [], "today": [], "soon": []};  # jac:ignore[W1037]
    if home is None {
        return lists;
    }
    tz: str = home["cinema"]["timezone"];
    today = cinema_today(tz);
    for s in home["page"]["sections"] {
        kind: str = s["type"];
        if kind == "hero" and s["movie"] {
            lists["featured"] = [_film(s["movie"], tz, today)];
        } elif kind == "now_showing" {
            lists["films"] = [_film(m, tz, today) for m in s["movies"]];
        } elif kind == "today" and len(s["days"]) > 0 {
            lists["today"] = [
                _show(x, tz, today, "") for x in s["days"][0]["showtimes"]
            ];
        } elif kind == "coming_soon" {
            lists["soon"] = [_film(m, tz, today) for m in s["movies"]];
        }
    }
    if len(lists["featured"]) == 0 and len(lists["films"]) > 0 {
        lists["featured"] = [lists["films"][0]];
    }
    return lists;
}

glob POSTER_BOX: dict[str, str] = {
         "display": "block",
         "aspectRatio": "2 / 3",
         "objectFit": "cover",
         "maxWidth": "100%"
     },
     POSTER_EMPTY: dict[str, str] = {
         "display": "flex",
         "alignItems": "flex-end",
         "aspectRatio": "2 / 3",
         "maxWidth": "100%",
         "width": "100%",
         "padding": "12px",
         "boxSizing": "border-box",
         "overflow": "hidden",
         "background": "linear-gradient(160deg, rgba(128, 128, 128, 0.28), rgba(128, 128, 128, 0.1))"
     },
     POSTER_EMPTY_TITLE: dict[str, str] = {
         "fontWeight": "600",
         "fontSize": "0.875rem",
         "lineHeight": "1.2",
         "textTransform": "uppercase",
         "letterSpacing": "0.04em",
         "opacity": "0.85"
     };

def AiPoster(
    slug: str, movie_key: str, alt: str, className: str, title: str = ""
) -> JsxElement {
    # A poster for the template's <img data-img="film.poster">, loaded like any poster.
    [src, set_src] = useState("");

    async def load {
        if not movie_key {
            return;
        }
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_poster(slug, movie_key);
        } except Exception as e {
            console.warn("poster load failed", e);
            return;
        }
        set_src(shown["poster"] if shown["ok"] else "");
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, movie_key]);
    # Whatever the written CSS says, a poster keeps its 2:3 shape and fills it, and a
    # missing one holds the same space: a row of cards stays even.
    if not src {
        return
            <span
                role="img"
                aria-label={alt}
                className={className}
                style={POSTER_EMPTY}
            >
                <span style={POSTER_EMPTY_TITLE}>{title or alt}</span>
            </span>;
    }
    return
        <img
            src={src}
            alt={alt}
            loading="lazy"
            className={className}
            style={POSTER_BOX}
        />;
}

def _camel(name: str) -> str {
    # stroke-width -> strokeWidth, as React names SVG attributes.
    parts = name.split("-");
    out = parts[0];
    for p in parts[1:] {
        out = out + p[:1].upper() + p[1:];
    }
    return out;
}

def _props(el: any, svg: bool) -> dict[str, any] {  # jac:ignore[W1037]
    # The element's attributes React may draw: never an event, a src or an outside href.
    props: dict[str, any] = {};  # jac:ignore[W1037]
    attrs: any = el.attributes;  # jac:ignore[W1037]
    for i in range(attrs.length) {
        a: any = attrs[i];  # jac:ignore[W1037]
        name: str = a.name;
        value: str = a.value;
        low = name.lower();
        if low.startswith("on") or low == "src" or low == "srcset" or low == "style" {
            continue;
        }
        if low == "href" or low == "xlink:href" {
            if svg and value.startswith("#") {
                props["href"] = value;
            }
            continue;
        }
        if low.startswith("data-") or low.startswith("aria-") {
            props[low] = value;
        } elif REACT_NAMES[low] {
            props[REACT_NAMES[low]] = value;
        } elif svg {
            props[_camel(name)] = value;
        } else {
            props[low] = value;
        }
    }
    return props;
}

obj Fill {
    # What a template is filled with: the cinema, its lists and where links go.
    has slug: str,
        cinema: str,
        logo: str,
        lists: dict[str, any],  # jac:ignore[W1037]
        motifs: list[str] = [];
}

def _motif_style(mask: str) -> dict[str, str] {
    # The figure painted in the element's own colour through its mask.
    url = f"url({mask})";
    return {
        "display": "inline-block",
        "backgroundColor": "currentColor",
        "maskImage": url,
        "WebkitMaskImage": url,
        "maskSize": "contain",
        "WebkitMaskSize": "contain",
        "maskRepeat": "no-repeat",
        "WebkitMaskRepeat": "no-repeat",
        "maskPosition": "center",
        "WebkitMaskPosition": "center"
    };
}

def _href(fill: Fill, link: str, scope: dict[str, any]) -> str {  # jac:ignore[W1037]
    base = f"/c/{fill.slug}";
    if link == "movies" {
        return f"{base}/movies";
    }
    if link == "showtimes" or link == "book" {
        return f"{base}#showtimes";
    }
    if link == "soon" {
        return f"{base}#coming-soon";
    }
    if link == "signin" {
        return f"{base}/sign-in";
    }
    if link == "tickets" {
        return f"{base}/my-tickets";
    }
    if link == "film" and scope["_film"] {
        return f"{base}/m/{scope['_film']}";
    }
    if link == "show" and scope["_show"] {
        return f"{base}/s/{scope['_show']}";
    }
    return base;
}

def _text_of(fill: Fill, key: str, scope: dict[str, any]) -> str {  # jac:ignore[W1037]
    if key == "cinema.name" {
        return fill.cinema;
    }
    value: str = scope[key] or "";
    return value;
}

def _kids(fill: Fill, el: any, scope: dict[str, any], key: str) -> list[any] {  # jac:ignore[W1037]
    # The element's children drawn, with lists repeated and empty states decided.
    out: list[any] = [];  # jac:ignore[W1037]
    nodes: any = el.childNodes;  # jac:ignore[W1037]
    for i in range(nodes.length) {
        child: any = nodes[i];  # jac:ignore[W1037]
        if child.nodeType == 3 {
            out.append(child.textContent);
            continue;
        }
        if child.nodeType != 1 {
            continue;
        }
        each: str = child.getAttribute("data-each") or "";
        if each {
            items: list[dict[str, any]] = (scope["times"] or [])  # jac:ignore[W1037]
                if each == "film.times"
                else (fill.lists[each] or []);
            for (n, item) in enumerate(items) {
                inner: dict[str, any] = {};  # jac:ignore[W1037]
                for k in Object.keys(scope) {  # jac:ignore[W2001]
                    inner[k] = scope[k];
                }
                for k in Object.keys(item) {  # jac:ignore[W2001]
                    inner[k] = item[k];
                }
                out.append(_draw(fill, child, inner, f"{key}.{i}.{n}"));
            }
            continue;
        }
        empty: str = child.getAttribute("data-empty") or "";
        if empty and len(fill.lists[empty] or []) > 0 {
            continue;
        }
        drawn = _draw(fill, child, scope, f"{key}.{i}");
        if drawn is not None {
            out.append(drawn);
        }
    }
    return out;
}

def _draw(fill: Fill, el: any, scope: dict[str, any], key: str) -> any {  # jac:ignore[W1037]
    # One element of the template as a React element, filled from `scope`.
    svg = el.namespaceURI == SVG_NS;
    tag: str = el.tagName if svg else el.tagName.toLowerCase();
    if tag in DROP {
        return None;
    }
    props = _props(el, svg);
    props["key"] = key;
    motif: str = el.getAttribute("data-motif") or "";
    if motif {
        if len(fill.motifs) == 0 {
            return None;
        }
        mask = fill.motifs[0]
            if motif == "single"
            else fill.motifs[len(fill.motifs) - 1];
        props["style"] = _motif_style(mask);
        props["aria-hidden"] = "true";
        return make(tag, props, []);
    }
    img: str = el.getAttribute("data-img") or "";
    if tag == "img" {
        alt: str = el.getAttribute("alt") or "";
        cls: str = el.getAttribute("class") or "";
        if img == "logo" and fill.logo {
            return
                <img
                    key={key}
                    src={fill.logo}
                    alt={alt or fill.cinema}
                    className={cls}
                />;
        }
        if img == "logo" {
            return <span key={key} className={cls}>{fill.cinema}</span>;
        }
        return
            <AiPoster
                key={key}
                slug={fill.slug}
                movie_key={scope["_poster"] or ""}
                alt={alt or scope["film.title"] or "Poster"}
                title={scope["film.title"] or ""}
                className={cls}
            />;
    }
    text: str = el.getAttribute("data-text") or "";
    kids: list[any] = [_text_of(fill, text, scope)]  # jac:ignore[W1037]
        if text
        else _kids(fill, el, scope, key);
    link: str = el.getAttribute("data-link") or "";
    if tag == "a" {
        to = _href(fill, link, scope);
        if "#" in to {
            props["href"] = to;
            return make("a", props, kids);
        }
        props["to"] = to;
        return make(Link, props, kids);
    }
    return make(tag, props, kids);
}

def:pub AiPart(
    slug: str,
    page: dict[str, str],
    part: str,
    cinema: str,
    logo: str = "",
    home: dict[str, any] | None = None,  # jac:ignore[W1037]
    motifs: list[str] | None = None
) -> JsxElement {
    # One part of the written page (header, home or footer) inside the stylesheet's
    # wrapper; nothing when the template has no such part. `motifs` are the brand kit's
    # masks as data URLs, single figure first.
    win: any = window;  # jac:ignore[W1037,W2001]
    parser: any = new(win.DOMParser);  # jac:ignore[W1037]
    doc: any = parser.parseFromString(f"<body>{page['html']}</body>", "text/html");  # jac:ignore[W1037]
    found: any = doc.body.querySelector(f'[data-part="{part}"]');  # jac:ignore[W1037]
    if not found {
        return <span className="hidden"/>;
    }
    fill = Fill(
        slug=slug, cinema=cinema, logo=logo, lists=ai_lists(home), motifs=motifs or []
    );
    return
        <div className="ai-page" data-ai-part={part} data-testid={f"ai-{part}"}>
            {_draw(fill, found, {}, part)}
        </div>;
}
