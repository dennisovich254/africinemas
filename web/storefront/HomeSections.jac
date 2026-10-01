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
import from .StorefrontParts { Poster, ShowtimeLink }
import from .showtimes { details_line, where_label }

glob HEADINGS: dict[str, str] = {
         "today": "Today",
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
    showtimes: list[dict[str, any]] = movie["next"];  # jac:ignore[W1037]
    return
        <li
            data-testid="movie-card"
            className="grid grid-cols-[6rem_1fr] gap-4 rounded-lg border bg-card p-4 @xl:grid-cols-[7.5rem_1fr]"
        >
            <Poster
                slug={slug}
                movie_key={movie["movie_key"]}
                has_poster={movie["has_poster"]}
            />
            <div className="flex min-w-0 flex-col gap-3">
                <div className="flex flex-col gap-1">
                    <h3 className="font-display text-2xl leading-tight">
                        <AppLink
                            to={f"/c/{slug}/m/{movie['movie_key']}"}
                            className="inline-flex min-h-11 items-center underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                        >
                            {movie["title"]}
                        </AppLink>
                    </h3>
                    <p className="text-sm text-muted-foreground">
                        {details_line(movie)}
                    </p>
                </div>
                <ul aria-label="Next showtimes" className="flex flex-wrap gap-2">
                    {[
                        <li key={s["screening_id"]}>
                            <ShowtimeLink
                                slug={slug}
                                showtime={s}
                                tz={tz}
                                with_day={True}
                            />
                        </li> for s in showtimes
                    ]}
                </ul>
            </div>
        </li>;
}

def Hero(slug: str, section: dict[str, any], template: str) -> JsxElement {  # jac:ignore[W1037]
    # The featured movie (if any) beside the cinema's headline and text.
    fields: dict[str, str] = section["fields"];
    movie: dict[str, any] | None = section["movie"];  # jac:ignore[W1037]
    big: bool = template == "marquee";
    on_sale: bool = movie is not None and "next" in movie;
    columns: str = "";
    if movie is not None {
        columns = "@xl:grid-cols-[14rem_1fr] @4xl:grid-cols-[18rem_1fr]"
            if big
            else "grid-cols-[6rem_1fr]";
    }
    return
        <section
            data-testid="section-hero"
            className={f"grid gap-6 rounded-lg border bg-card p-4 @xl:p-6 {columns}"}
        >
            {movie is not None
                and <div className={"w-40 @xl:w-full" if big else ""}>
                    <Poster
                        slug={slug}
                        movie_key={movie["movie_key"]}
                        has_poster={movie["has_poster"]}
                    />
                </div>}
            <div className="flex min-w-0 flex-col justify-center gap-3">
                <h2
                    className={"font-display leading-none "
                        + ("text-4xl @xl:text-5xl" if big else "text-3xl")}
                >
                    {fields["headline"]
                        or (movie["title"] if movie is not None else "")}
                </h2>
                {fields["text"]
                    and <p className="max-w-prose text-muted-foreground">
                        {fields["text"]}
                    </p>}
                {movie is not None
                    and fields["headline"]
                    and <p className="font-display text-2xl leading-tight">
                        {movie["title"]}
                    </p>}
                {movie is not None
                    and <p className="text-sm text-muted-foreground">
                        {details_line(movie)}
                    </p>}
                {on_sale
                    and <AppLink
                        to={f"/c/{slug}/m/{movie['movie_key']}"}
                        testid="hero-cta"
                        className="inline-flex min-h-11 w-fit items-center rounded-md bg-primary px-5 font-medium text-primary-foreground hover:bg-primary/90"
                    >
                        See showtimes
                    </AppLink>}
                {movie is not None
                    and not on_sale
                    and <p
                        className="w-fit rounded-md bg-secondary px-2 py-0.5 text-sm font-medium text-secondary-foreground"
                    >
                        Coming soon
                    </p>}
            </div>
        </section>;
}

def Today(slug: str, section: dict[str, any], tz: str) -> JsxElement {  # jac:ignore[W1037]
    showtimes: list[dict[str, any]] = section["showtimes"];  # jac:ignore[W1037]
    return
        <section data-testid="section-today" className="flex flex-col gap-4">
            <SectionHeading text={heading_of(section)}/>
            <ul className="flex flex-col divide-y rounded-lg border bg-card">
                {[
                    <li
                        key={s["screening_id"]}
                        className="flex items-center gap-4 px-4 py-2"
                    >
                        <ShowtimeLink slug={slug} showtime={s} tz={tz}/>
                        <div className="flex min-w-0 flex-col">
                            <span className="truncate font-medium">{s["title"]}</span>
                            <span className="text-sm text-muted-foreground">
                                {where_label(s)}
                            </span>
                        </div>
                    </li> for s in showtimes
                ]}
            </ul>
        </section>;
}

def NowShowing(
    slug: str,
    section: dict[str, any],  # jac:ignore[W1037]
    tz: str,
    template: str
) -> JsxElement {
    movies: list[dict[str, any]] = section["movies"];  # jac:ignore[W1037]
    return
        <section data-testid="section-now_showing" className="flex flex-col gap-4">
            <SectionHeading text={heading_of(section)}/>
            <ul
                className={"grid gap-4 "
                    + ("@4xl:grid-cols-2" if template == "marquee" else "")}
            >
                {[
                    <MovieCard key={m["movie_key"]} slug={slug} movie={m} tz={tz}/>
                    for m in movies
                ]}
            </ul>
        </section>;
}

def ComingSoon(slug: str, section: dict[str, any], template: str) -> JsxElement {  # jac:ignore[W1037]
    movies: list[dict[str, any]] = section["movies"];  # jac:ignore[W1037]
    return
        <section data-testid="section-coming_soon" className="flex flex-col gap-4">
            <SectionHeading text={heading_of(section)}/>
            <ul
                className={"grid gap-4 "
                    + (
                        "grid-cols-2 @xl:grid-cols-3 @4xl:grid-cols-4"
                            if template != "compact"
                            else "grid-cols-2"
                    )}
            >
                {[
                    <li key={m["movie_key"]} className="flex flex-col gap-2">
                        <Poster
                            slug={slug}
                            movie_key={m["movie_key"]}
                            has_poster={m["has_poster"]}
                        />
                        <h3 className="font-display text-xl leading-tight">
                            {m["title"]}
                        </h3>
                        <p className="text-sm text-muted-foreground">
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
            <div className="flex flex-col gap-3 rounded-lg border bg-card p-4">
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
        return <NowShowing slug={slug} section={section} tz={tz} template={template}/>;
    }
    if kind == "coming_soon" {
        return <ComingSoon slug={slug} section={section} template={template}/>;
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
