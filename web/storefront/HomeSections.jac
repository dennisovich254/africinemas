"""The sections of a cinema's home page (P4.1b), as public_home fills them in.

Each section is drawn from its type and the page's template: Marquee leads with a large
featured movie and lays what's on in two columns, Schedule leads with today's showtimes
and lists movies in one column, and Compact is one narrow scrolling list. A section's
own title replaces its default heading. Text is shown as plain text, with its line
breaks; links to other sites open in a new tab.

Sections lay out by the width of their container (Tailwind container queries: @xl is
36rem, @4xl is 56rem), not the window's, so they look the same on the storefront and
in the editor's preview at any size. The page puts them in an `@container`.
"""

import from react { useState, useEffect }
import from ..shell.AppLink { AppLink }
import from core.catalog.storefront_api { public_home_photo }
import from .StorefrontParts { Poster, Backdrop, Thumb, ShowtimeLink }
import from .showtimes {
    details_line,
    where_label,
    day_label,
    time_label,
    cinema_today,
    date_label,
    by_movie,
    release_label,
    sorted_unique,
    listed,
    runtime_label
}

glob HEADINGS: dict[str, str] = {
         "today": "What's on",
         "now_showing": "Now showing",
         "coming_soon": "Coming soon",
         "about": "About us",
         "location": "Find us",
         "contact": "Contact",
         "faq": "Questions"
     },
     EXTERNAL: str = "inline-flex min-h-11 items-center font-medium text-primary underline underline-offset-4 hover:no-underline";

def heading_of(section: dict[str, any]) -> str {  # jac:ignore[W1037]
    title: str = section["fields"].get("title", "") or "";
    return title or HEADINGS.get(section["type"], "");
}

def SectionHeading(text: str) -> JsxElement {
    return <h2 className="font-display text-3xl leading-none @xl:text-4xl">{text}</h2>;
}

def:pub MovieCard(slug: str, movie: dict[str, any], tz: str) -> JsxElement {  # jac:ignore[W1037]
    # A movie on sale as a poster-led card: the poster, its title and details, and its
    # next showtime. The whole card leads to the movie's page.
    upcoming: list[dict[str, any]] = movie["next"];  # jac:ignore[W1037]
    soonest: dict[str, any] | None = upcoming[0] if len(upcoming) > 0 else None;  # jac:ignore[W1037]
    return
        <li data-testid="movie-card" className="min-w-0">
            <AppLink
                to={f"/c/{slug}/m/{movie['movie_key']}"}
                className="group flex flex-col gap-2 rounded-lg focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring"
            >
                <Poster
                    slug={slug}
                    movie_key={movie["movie_key"]}
                    has_poster={movie["has_poster"]}
                    className="shadow-sm transition-transform duration-200 group-hover:-translate-y-1 motion-reduce:transition-none motion-reduce:group-hover:translate-y-0"
                />
                <h3
                    className="font-display text-xl leading-tight group-hover:underline group-hover:underline-offset-4"
                >
                    {movie["title"]}
                </h3>
            </AppLink>
            <p className="text-sm text-muted-foreground">{details_line(movie)}</p>
            {soonest is not None
                and <p className="text-sm">
                    {f"Next: {day_label(soonest['starts_at'], tz)}, {time_label(
                        soonest['starts_at'], tz
                    )}"}
                </p>}
        </li>;
}

def Hero(slug: str, section: dict[str, any], template: str) -> JsxElement {  # jac:ignore[W1037]
    # The page's one bold moment: the featured movie over its backdrop (or its blurred
    # poster), the cinema's headline, and Book tickets. Marquee makes it tall; the
    # other templates keep it slim.
    fields: dict[str, str] = section["fields"];
    movie: dict[str, any] | None = section["movie"];  # jac:ignore[W1037]
    big: bool = template == "marquee";
    on_sale: bool = movie is not None and "next" in movie;
    title: str = movie["title"] if movie is not None else fields["headline"];
    return
        <section
            data-testid="section-hero"
            className={"relative isolate flex items-end overflow-hidden rounded-xl border bg-card "
                + ("min-h-[22rem] @xl:min-h-[28rem]" if big else "min-h-[14rem]")}
        >
            {movie is not None and <Backdrop slug={slug} movie={movie}/>}
            <div
                aria-hidden="true"
                className="absolute inset-0 -z-10 bg-linear-to-t from-card via-card/85 to-card/20"
            />
            <div
                className={"landing-rise grid w-full items-end gap-5 p-5 @xl:p-8 "
                    + (
                        "@xl:grid-cols-[10rem_1fr] @4xl:grid-cols-[12rem_1fr]"
                            if movie is not None
                            else ""
                    )}
            >
                {movie is not None
                    and <div className="hidden w-full @xl:block">
                        <Poster
                            slug={slug}
                            movie_key={movie["movie_key"]}
                            has_poster={movie["has_poster"]}
                            className="shadow-lg"
                        />
                    </div>}
                <div className="flex min-w-0 max-w-2xl flex-col gap-3">
                    {movie is not None
                        and fields["headline"]
                        and <p
                            className="text-sm font-semibold uppercase tracking-wide text-primary"
                        >
                            {fields["headline"]}
                        </p>}
                    <h2
                        className={"font-display leading-none "
                            + (
                                "text-5xl @xl:text-6xl"
                                    if big
                                    else "text-4xl @xl:text-5xl"
                            )}
                    >
                        {title}
                    </h2>
                    {movie is not None
                        and <p className="text-sm text-muted-foreground">
                            {details_line(movie)}{movie.get("language")
                                and f" · {movie['language']}"}
                        </p>}
                    {fields["text"]
                        and <p className="max-w-prose text-pretty">{fields["text"]}</p>}
                    {on_sale
                        and <div className="flex flex-wrap gap-3">
                            <AppLink
                                to={f"/c/{slug}/m/{movie['movie_key']}"}
                                testid="hero-cta"
                                className="inline-flex min-h-11 w-fit items-center rounded-md bg-primary px-6 font-semibold text-primary-foreground transition-colors hover:bg-primary/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                            >
                                Book tickets
                            </AppLink>
                            <a
                                href="#showtimes"
                                data-testid="hero-showtimes"
                                className="inline-flex min-h-11 w-fit items-center rounded-md border bg-card/70 px-5 font-medium transition-colors hover:bg-card focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                            >
                                View showtimes
                            </a>
                        </div>}
                    {movie is not None
                        and not on_sale
                        and <p
                            className="w-fit rounded-md bg-secondary px-3 py-1 text-sm font-medium text-secondary-foreground"
                        >
                            Coming soon
                        </p>}
                </div>
            </div>
        </section>;
}

def:pub GenreChips(
    genres: list[str],
    chosen: str,
    on_choose: any,  # jac:ignore[W1037]
    testid: str
) -> JsxElement {
    # "All" and one chip per genre; nothing when there's only one genre to choose.
    if len(genres) < 2 {
        return <span className="hidden"/>;
    }
    chip = "inline-flex min-h-11 shrink-0 items-center rounded-full border px-4 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring ";
    on = "border-foreground bg-foreground text-background";
    off = "bg-card hover:border-foreground";
    return
        <div
            role="group"
            aria-label="Filter by genre"
            data-testid={testid}
            className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1"
        >
            <button
                type="button"
                aria-pressed={"true" if not chosen else "false"}
                onClick={lambda { on_choose(""); }}
                className={chip + (on if not chosen else off)}
            >
                All
            </button>
            {[
                <button
                    key={g}
                    type="button"
                    aria-pressed={"true" if g == chosen else "false"}
                    onClick={lambda { on_choose(g); }}
                    className={chip + (on if g == chosen else off)}
                >
                    {g}
                </button> for g in genres
            ]}
        </div>;
}

def DayMovie(slug: str, group: dict[str, any], tz: str) -> JsxElement {  # jac:ignore[W1037]
    # One movie on the chosen day: its poster, title and details, and its times. A time
    # is the way in: it opens that showtime, where booking continues.
    showtimes: list[dict[str, any]] = group["showtimes"];  # jac:ignore[W1037]
    return
        <li
            data-testid="day-movie"
            className="grid grid-cols-[4.5rem_1fr] gap-4 py-4 @xl:grid-cols-[5.5rem_1fr]"
        >
            <Poster
                slug={slug}
                movie_key={group["movie_key"]}
                has_poster={group["has_poster"]}
            />
            <div className="flex min-w-0 flex-col gap-2">
                <div className="flex flex-col">
                    <h3 className="font-display text-xl leading-tight">
                        <AppLink
                            to={f"/c/{slug}/m/{group['movie_key']}"}
                            className="inline-flex min-h-11 min-w-11 items-center underline-offset-4 hover:underline"
                        >
                            {group["title"]}
                        </AppLink>
                    </h3>
                    <p className="text-sm text-muted-foreground">
                        {details_line(group)}
                    </p>
                </div>
                <ul
                    aria-label={f"{group['title']} times"}
                    className="flex flex-wrap gap-2"
                >
                    {[
                        <li key={s["screening_id"]}>
                            <ShowtimeLink
                                slug={slug}
                                showtime={s}
                                tz={tz}
                                with_place={True}
                            />
                        </li> for s in showtimes
                    ]}
                </ul>
            </div>
        </li>;
}

def Today(slug: str, section: dict[str, any], tz: str) -> JsxElement {  # jac:ignore[W1037]
    # What's on: the coming days (Today first), genre chips when there's a choice, and
    # the chosen day's movies with their times. Tapping a time opens that showtime.
    days: list[dict[str, any]] = section["days"];  # jac:ignore[W1037]
    [chosen, set_chosen] = useState(0);
    [genre, set_genre] = useState("");
    index: int = chosen if chosen < len(days) else 0;
    today = cinema_today(tz);
    day: dict[str, any] = days[index];  # jac:ignore[W1037]
    groups = by_movie(day["showtimes"]);
    genres = sorted_unique([g for m in groups for g in m["genres"]]);
    active: str = genre if listed(genre, genres) else "";
    shown = [
        m
        for m in groups
        if not active or listed(active, m["genres"])
    ];
    return
        <section
            id="showtimes"
            data-testid="section-today"
            className="flex scroll-mt-24 flex-col gap-4"
        >
            <SectionHeading text={heading_of(section)}/>
            <div
                role="group"
                aria-label="Choose a day"
                data-testid="day-strip"
                className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1"
            >
                {[
                    <button
                        key={d["date"]}
                        type="button"
                        data-testid="day-option"
                        aria-pressed={"true" if i == index else "false"}
                        onClick={lambda { set_chosen(i); }}
                        className={"inline-flex min-h-11 shrink-0 items-center rounded-full border px-4 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring "
                            + (
                                "border-primary bg-primary text-primary-foreground"
                                    if i == index
                                    else "bg-card hover:border-primary"
                            )}
                    >
                        {date_label(d["date"], today)}
                    </button> for (i, d) in enumerate(days)
                ]}
            </div>
            <GenreChips
                genres={genres}
                chosen={active}
                on_choose={set_genre}
                testid="genre-chips"
            />
            <ul
                aria-live="polite"
                data-testid="day-showtimes"
                className="flex flex-col divide-y rounded-xl border bg-card px-4"
            >
                {[
                    <DayMovie key={g["movie_key"]} slug={slug} group={g} tz={tz}/>
                    for g in shown
                ]}
            </ul>
        </section>;
}

def:pub NowShowing(  # jac:ignore[W3030] the cinema, section, time zone, template and two switches
    slug: str,
    section: dict[str, any],  # jac:ignore[W1037]
    tz: str,
    template: str,
    view_all: bool = False,
    chips: bool = False
) -> JsxElement {
    # The movies on sale as poster cards. On the home page, a row with View all; on the
    # Movies page (`chips`), with genre chips above.
    movies: list[dict[str, any]] = section["movies"];  # jac:ignore[W1037]
    [genre, set_genre] = useState("");
    genres = sorted_unique([g for m in movies for g in m["genres"]]);
    active: str = genre if listed(genre, genres) else "";
    shown = [
        m
        for m in movies
        if not active or listed(active, m["genres"])
    ];
    return
        <section
            id="now-showing"
            data-testid="section-now_showing"
            className="flex scroll-mt-24 flex-col gap-4"
        >
            <div className="flex flex-wrap items-end justify-between gap-3">
                <SectionHeading text={heading_of(section)}/>
                {view_all
                    and <AppLink
                        to={f"/c/{slug}/movies"}
                        testid="view-all-movies"
                        className="inline-flex min-h-11 items-center rounded-full bg-primary px-4 text-sm font-semibold text-primary-foreground hover:bg-primary/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                    >
                        View all
                    </AppLink>}
            </div>
            {chips
                and <GenreChips
                    genres={genres}
                    chosen={active}
                    on_choose={set_genre}
                    testid="movie-genre-chips"
                />}
            <ul
                className={"grid grid-cols-2 gap-x-4 gap-y-6 "
                    + (
                        ""
                            if template == "compact"
                            else "@xl:grid-cols-3 @4xl:grid-cols-4"
                    )}
            >
                {[
                    <MovieCard key={m["movie_key"]} slug={slug} movie={m} tz={tz}/>
                    for m in shown
                ]}
            </ul>
        </section>;
}

def:pub ComingSoon(slug: str, section: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    # A row of posters that swipes sideways when it's wider than the page.
    movies: list[dict[str, any]] = section["movies"];  # jac:ignore[W1037]
    return
        <section
            id="coming-soon"
            data-testid="section-coming_soon"
            className="flex scroll-mt-24 flex-col gap-4"
        >
            <SectionHeading text={heading_of(section)}/>
            <ul className="-mx-1 flex snap-x gap-4 overflow-x-auto px-1 pb-2">
                {[
                    <li
                        key={m["movie_key"]}
                        className="flex w-32 shrink-0 snap-start flex-col gap-2 @xl:w-40"
                    >
                        <Poster
                            slug={slug}
                            movie_key={m["movie_key"]}
                            has_poster={m["has_poster"]}
                        />
                        <h3 className="font-display text-lg leading-tight">
                            {m["title"]}
                        </h3>
                        {m.get("release_date")
                            and <p className="text-sm font-medium">
                                {release_label(m["release_date"])}
                            </p>}
                        <p className="text-xs text-muted-foreground">
                            {details_line(m)}
                        </p>
                    </li> for m in movies
                ]}
            </ul>
        </section>;
}

def HomePhoto(slug: str, photo: str, label: str) -> JsxElement {
    # A photo the page shows: a data URL already (the editor's preview), or loaded by
    # name. It keeps its 4:3 frame while it loads.
    [src, set_src] = useState(photo if photo.startswith("data:") else "");

    async def load {
        if photo.startswith("data:") {
            set_src(photo);
            return;
        }
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_home_photo(slug, photo);
        } except Exception as e {
            console.warn("photo load failed", e);
            return;
        }
        set_src(shown["photo"] if shown["ok"] else "");
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, photo]);

    return
        <div className="aspect-[4/3] overflow-hidden rounded-lg bg-muted">
            {src
                and <img
                    src={src}
                    alt={label}
                    loading="lazy"
                    className="h-full w-full object-cover"
                />}
        </div>;
}

def About(slug: str, section: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    text: str = section["fields"]["text"];
    photos: list[str] = section["fields"].get("photos", []) or [];
    heading = heading_of(section);
    return
        <section data-testid="section-about" className="flex flex-col gap-4">
            <SectionHeading text={heading}/>
            {text
                and <p className="max-w-prose whitespace-pre-line leading-relaxed">
                    {text}
                </p>}
            {len(photos) > 0
                and <div
                    data-testid="about-photos"
                    className="grid grid-cols-2 gap-3 @xl:grid-cols-4"
                >
                    {[
                        <HomePhoto
                            key={f"{i}"}
                            slug={slug}
                            photo={p}
                            label={f"{heading}, photo {i + 1}"}
                        /> for (i, p) in enumerate(photos)
                    ]}
                </div>}
        </section>;
}

def Location(section: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    fields: dict[str, any] = section["fields"];  # jac:ignore[W1037]
    hours: list[dict[str, str]] = fields["hours"];
    return
        <section data-testid="section-location" className="flex flex-col gap-4">
            <SectionHeading text={heading_of(section)}/>
            <div className="flex flex-col gap-3">
                {fields["address"]
                    and <p className="whitespace-pre-line">{fields["address"]}</p>}{fields[
                    "map_url"
                ]
                    and <a
                        href={fields["map_url"]}
                        target="_blank"
                        rel="noopener noreferrer"
                        className={EXTERNAL}
                    >
                        Open in maps
                    </a>}{len(hours) > 0
                    and <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-1">
                        {[
                            <div key={f"{i}"} className="contents">
                                <dt className="text-muted-foreground">{h["days"]}</dt>
                                <dd className="font-medium tabular-nums">
                                    {h["times"]}
                                </dd>
                            </div> for (i, h) in enumerate(hours)
                        ]}
                    </dl>}
            </div>
        </section>;
}

def Contact(section: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    fields: dict[str, any] = section["fields"];  # jac:ignore[W1037]
    links: list[dict[str, str]] = fields["links"];
    phone: str = fields["phone"];
    dial: str = phone.replace(" ", "");
    return
        <section data-testid="section-contact" className="flex flex-col gap-4">
            <SectionHeading text={heading_of(section)}/>
            <ul className="flex flex-col gap-1">
                {phone
                    and <li>
                        <a href={f"tel:{dial}"} className={EXTERNAL}>{phone}</a>
                    </li>}{fields["email"]
                    and <li>
                        <a href={f"mailto:{fields['email']}"} className={EXTERNAL}>
                            {fields["email"]}
                        </a>
                    </li>}{[
                    <li key={f"{i}"}>
                        <a
                            href={link["url"]}
                            target="_blank"
                            rel="noopener noreferrer"
                            className={EXTERNAL}
                        >
                            {link["label"] or link["url"]}
                        </a>
                    </li> for (i, link) in enumerate(links)
                ]}
            </ul>
        </section>;
}

def Faq(section: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    items: list[dict[str, str]] = section["fields"]["items"];
    return
        <section data-testid="section-faq" className="flex flex-col gap-4">
            <SectionHeading text={heading_of(section)}/>
            <div className="flex flex-col divide-y rounded-lg border bg-card">
                {[
                    <details key={f"{i}"} className="group px-4">
                        <summary
                            className="flex min-h-11 cursor-pointer items-center py-2 font-medium"
                        >
                            {item["question"]}
                        </summary>
                        <p className="whitespace-pre-line pb-4 text-muted-foreground">
                            {item["answer"]}
                        </p>
                    </details> for (i, item) in enumerate(items)
                ]}
            </div>
        </section>;
}

def:pub HomeSection(
    slug: str,
    section: dict[str, any],  # jac:ignore[W1037]
    tz: str,
    template: str
) -> JsxElement {
    kind: str = section["type"];
    if kind == "hero" {
        return <Hero slug={slug} section={section} template={template}/>;
    }
    if kind == "today" {
        return <Today slug={slug} section={section} tz={tz}/>;
    }
    if kind == "now_showing" {
        return
            <NowShowing
                slug={slug}
                section={section}
                tz={tz}
                template={template}
                view_all={True}
            />;
    }
    if kind == "coming_soon" {
        return <ComingSoon slug={slug} section={section}/>;
    }
    if kind == "about" {
        return <About slug={slug} section={section}/>;
    }
    if kind == "location" {
        return <Location section={section}/>;
    }
    if kind == "contact" {
        return <Contact section={section}/>;
    }
    return <Faq section={section}/>;
}

glob VISIT_TYPES: list[str] = ["location", "contact", "faq"];

def:pub home_blocks(sections: list[dict[str, any]]) -> list[list[dict[str, any]]] {  # jac:ignore[W1037]
    # The page's sections, with each run of Visit us sections (location, contact,
    # questions) gathered into one band.
    blocks: list[list[dict[str, any]]] = [];  # jac:ignore[W1037]
    for s in sections {
        last = blocks[len(blocks) - 1] if len(blocks) > 0 else [];
        if s["type"] in VISIT_TYPES
            and len(last) > 0
            and last[0]["type"] in VISIT_TYPES {
            last.append(s);
        } else {
            blocks.append([s]);
        }
    }
    return blocks;
}

def:pub nav_links(sections: list[dict[str, any]]) -> list[list[str]] {  # jac:ignore[W1037]
    # The header's links to the sections this page shows.
    kinds = [s["type"] for s in sections];
    links: list[list[str]] = [];
    if "today" in kinds {
        links.append(["What's on", "#showtimes"]);
    } elif "now_showing" in kinds {
        links.append(["What's on", "#now-showing"]);
    }
    if "coming_soon" in kinds {
        links.append(["Coming soon", "#coming-soon"]);
    }
    if any(k in VISIT_TYPES for k in kinds) {
        links.append(["Visit us", "#visit-us"]);
    }
    return links;
}

def:pub HomeBlock(
    slug: str,
    block: list[dict[str, any]],  # jac:ignore[W1037]
    tz: str,
    template: str
) -> JsxElement {
    # One section, or the Visit us band of location, contact and questions together.
    if block[0]["type"] not in VISIT_TYPES {
        return
            <HomeSection slug={slug} section={block[0]} tz={tz} template={template}/>;
    }
    return
        <div
            id="visit-us"
            data-testid="visit-us"
            className={"grid scroll-mt-24 gap-10 rounded-xl border bg-card p-5 @xl:p-8 "
                + (
                    "@4xl:grid-cols-2"
                        if len(block) > 1 and template != "compact"
                        else ""
                )}
        >
            {[
                <HomeSection
                    key={s["type"]}
                    slug={slug}
                    section={s}
                    tz={tz}
                    template={template}
                /> for s in block
            ]}
        </div>;
}

def:pub for_venue(sections: list[dict[str, any]], venue: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The page's sections narrowed to one venue ("" for all): its showtimes by day and
    # the movies showing there. Sections left with nothing are dropped; the rest stay.
    if not venue {
        return sections;
    }
    narrowed: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in sections {
        if s["type"] == "today" {
            days = [];
            for d in s["days"] {
                here = [
                    x
                    for x in d["showtimes"]
                    if x["venue"]["name"] == venue
                ];
                if len(here) > 0 {
                    days.append({"date": d["date"], "showtimes": here});
                }
            }
            if len(days) > 0 {
                narrowed.append(
                    {"type": s["type"], "fields": s["fields"], "days": days}
                );
            }
        } elif s["type"] == "now_showing" {
            movies = [
                m
                for m in s["movies"]
                if listed(venue, m.get("venues"))
            ];
            if len(movies) > 0 {
                narrowed.append(
                    {"type": s["type"], "fields": s["fields"], "movies": movies}
                );
            }
        } else {
            narrowed.append(s);
        }
    }
    return narrowed;
}

def:pub FeaturedHero(
    slug: str,
    section: dict[str, any],  # jac:ignore[W1037]
    movies: list[dict[str, any]],  # jac:ignore[W1037]
    under_header: bool = True
) -> JsxElement {
    # The Marquee template's hero (P4.1d): full width, under the see-through header,
    # always in the theme's dark colours so the words read over the picture. The
    # featured movie first, then the others on sale, chosen with the picker on the right
    # (or under the words on phones). It never moves by itself.
    fields: dict[str, str] = section["fields"];
    featured: dict[str, any] | None = section["movie"];  # jac:ignore[W1037]
    choices: list[dict[str, any]] = [];  # jac:ignore[W1037]
    if featured is not None {
        choices.append(featured);
    }
    for m in movies {
        if len(choices) < 8
            and not any(c["movie_key"] == m["movie_key"] for c in choices) {
            choices.append(m);
        }
    }
    [index, set_index] = useState(0);
    current: int = index if index < len(choices) else 0;
    movie: dict[str, any] | None = choices[current] if len(choices) > 0 else None;  # jac:ignore[W1037]
    on_sale: bool = movie is not None and "next" in movie;
    count: int = len(choices);

    def step(delta: int) {
        set_index((current + delta + count) % count);
    }

    year: str = "";
    if movie is not None and movie.get("release_date") {
        year = movie["release_date"][:4];
    }
    pill = "inline-flex min-h-11 items-center rounded-full px-6 font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring";
    return
        <div className="dark">
            <section
                data-surface="storefront"
                data-testid="section-hero"
                data-movie={movie["movie_key"] if movie is not None else ""}
                aria-roledescription="featured movies"
                className={"@container relative isolate overflow-hidden bg-background text-foreground "
                    + ("-mt-[3.75rem]" if under_header else "rounded-xl")}
            >
                {movie is not None
                    and <Backdrop key={movie["movie_key"]} slug={slug} movie={movie}/>}
                <div
                    aria-hidden="true"
                    className="absolute inset-0 -z-10 bg-linear-to-r from-background via-background/75 to-background/10"
                />
                <div
                    aria-hidden="true"
                    className="absolute inset-x-0 bottom-0 -z-10 h-40 bg-linear-to-t from-background to-transparent"
                />
                <div
                    className={"mx-auto grid w-full max-w-5xl items-end gap-8 px-4 pb-10 @4xl:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)] "
                        + (
                            "min-h-[34rem] pt-28 md:min-h-[38rem]"
                                if under_header
                                else "min-h-[28rem] pt-10"
                        )}
                >
                    <div
                        key={movie["movie_key"] if movie is not None else "none"}
                        className="landing-rise flex min-w-0 flex-col gap-4"
                    >
                        {fields["headline"]
                            and <p
                                className="text-sm font-semibold uppercase tracking-wide text-primary"
                            >
                                {fields["headline"]}
                            </p>}
                        <h2
                            className="font-display text-5xl leading-none text-balance md:text-7xl"
                        >
                            {movie["title"]
                                if movie is not None
                                else fields["headline"]}
                        </h2>
                        {movie is not None
                            and <p
                                data-testid="hero-details"
                                className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground"
                            >
                                {movie["age_rating"]
                                    and <span
                                        className="rounded border border-current px-1.5 text-xs font-semibold text-foreground"
                                    >
                                        {movie["age_rating"]}
                                    </span>}{year and <span>{year}</span>}{movie[
                                    "runtime_minutes"
                                ]
                                    and <span>
                                        {runtime_label(movie["runtime_minutes"])}
                                    </span>}{len(movie["genres"] or []) > 0
                                    and <span>{", ".join(movie["genres"])}</span>}{movie.get(
                                    "language"
                                )
                                    and <span>{movie["language"]}</span>}
                            </p>}
                        {movie is not None
                            and movie.get("synopsis")
                            and <p className="max-w-prose text-pretty line-clamp-4">
                                {movie["synopsis"]}
                            </p>}
                        {fields["text"]
                            and <p className="max-w-prose text-pretty">
                                {fields["text"]}
                            </p>}
                        {on_sale
                            and <div className="flex flex-wrap gap-3 pt-2">
                                <AppLink
                                    to={f"/c/{slug}/m/{movie['movie_key']}"}
                                    testid="hero-cta"
                                    className={f"{pill} bg-primary text-primary-foreground hover:bg-primary/90"}
                                >
                                    Book tickets
                                </AppLink>
                                <a
                                    href="#showtimes"
                                    data-testid="hero-showtimes"
                                    className={f"{pill} bg-card/80 text-foreground hover:bg-card"}
                                >
                                    View showtimes
                                </a>
                            </div>}
                        {movie is not None
                            and not on_sale
                            and <p
                                className="w-fit rounded-full bg-secondary px-4 py-1.5 text-sm font-medium text-secondary-foreground"
                            >
                                {release_label(movie["release_date"])
                                    if movie.get("release_date")
                                    else "Coming soon"}
                            </p>}
                    </div>
                    {count > 1
                        and <div
                            data-testid="hero-picker"
                            className="flex min-w-0 flex-col gap-3"
                        >
                            <div className="flex items-center justify-between gap-2">
                                <h3 className="text-sm font-semibold">Now showing</h3>
                                <div className="flex gap-1">
                                    <button
                                        type="button"
                                        aria-label="Previous movie"
                                        onClick={lambda { step(-1); }}
                                        className="grid size-11 place-items-center rounded-full border bg-card/60 hover:bg-card"
                                    >
                                        <span aria-hidden="true">‹</span>
                                    </button>
                                    <button
                                        type="button"
                                        aria-label="Next movie"
                                        onClick={lambda { step(1); }}
                                        className="grid size-11 place-items-center rounded-full border bg-card/60 hover:bg-card"
                                    >
                                        <span aria-hidden="true">›</span>
                                    </button>
                                </div>
                            </div>
                            <ul
                                className="-mx-1 flex snap-x gap-3 overflow-x-auto px-1 pb-1"
                            >
                                {[
                                    <li
                                        key={c["movie_key"]}
                                        className="w-40 shrink-0 snap-start md:w-44"
                                    >
                                        <button
                                            type="button"
                                            data-testid="hero-choice"
                                            aria-pressed={"true"
                                                if i == current
                                                else "false"}
                                            aria-label={f"Feature {c['title']}"}
                                            onClick={lambda { set_index(i); }}
                                            className={"flex w-full flex-col gap-1.5 rounded-xl p-1 text-left focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring "
                                                + (
                                                    "ring-2 ring-primary"
                                                        if i == current
                                                        else "opacity-80 hover:opacity-100"
                                                )}
                                        >
                                            <Thumb slug={slug} movie={c}/>
                                            <span
                                                className="truncate px-1 text-sm font-medium"
                                            >
                                                {c["title"]}
                                            </span>
                                        </button>
                                    </li> for (i, c) in enumerate(choices)
                                ]}
                            </ul>
                            <div
                                className="flex justify-center"
                                role="group"
                                aria-label="Featured movie"
                            >
                                {[
                                    <button
                                        key={c["movie_key"]}
                                        type="button"
                                        aria-label={f"Show {c['title']}"}
                                        aria-current={"true" if i == current else None}
                                        onClick={lambda { set_index(i); }}
                                        className="grid size-11 place-items-center"
                                    >
                                        <span
                                            aria-hidden="true"
                                            className={"block h-1.5 rounded-full transition-all motion-reduce:transition-none "
                                                + (
                                                    "w-5 bg-primary"
                                                        if i == current
                                                        else "w-1.5 bg-muted-foreground/60"
                                                )}
                                        />
                                    </button> for (i, c) in enumerate(choices)
                                ]}
                            </div>
                        </div>}
                </div>
            </section>
        </div>;
}
