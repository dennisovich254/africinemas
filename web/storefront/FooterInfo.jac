"""The cinema's information inside the storefront's footer (P14.3a, ADR-0066).

Drawn by StorefrontShell inside the footer, whatever the cinema's design: in our own
footer, and appended inside the footer the AI wrote (AiPart's `inside`), so no design
can leave it out. Who runs the cinema and where, how to reach it (phone, email,
WhatsApp, support hours), its social media and links to its published policies
(P14.3b) and public documents, such as its licences (P14.3d). "Report this cinema"
(14.6) joins it. Every link was built on the server
from what the cinema typed (core/catalog/site_info.jac), never taken as typed.

Two quiet rows: who and where (with the socials), then how to reach it. It takes the
footer's own colours (its links too, whatever the design's CSS says), so it reads as
part of any design. Nothing shows for a cinema that hasn't filled it in.
"""

import from "@hugeicons/react" { HugeiconsIcon }
import from ..site { local_path }
import from "@hugeicons/core-free-icons" {
    Call02Icon,
    Mail01Icon,
    WhatsappIcon,
    Clock01Icon,
    Location01Icon,
    Facebook01Icon,
    InstagramIcon,
    NewTwitterIcon,
    TiktokIcon,
    YoutubeIcon
}

glob NETWORK_ICONS: dict[str, any] = {  # jac:ignore[W1037]
         "facebook": Facebook01Icon,
         "instagram": InstagramIcon,
         "x": NewTwitterIcon,
         "tiktok": TiktokIcon,
         "youtube": YoutubeIcon
     },
     LINK: str = "inline-flex min-h-11 items-center gap-2 underline-offset-4 hover:underline",
     # The footer's colour for our links: an AI design's `a` rule would win over a class.
     INHERIT: dict[str, str] = {"color": "inherit"};

def Reach(icon: any, children: any = None) -> JsxElement {  # jac:ignore[W1037]
    return
        <li className="inline-flex min-h-11 items-center gap-2">
            <HugeiconsIcon icon={icon} size={18} strokeWidth={2} aria-hidden="true"/>
            {children}
        </li>;
}

def:pub FooterInfo(
    slug: str,
    cinema: str,
    info: any,  # jac:ignore[W1037]
    policies: list[dict[str, str]] | None = None,
    documents: list[dict[str, str]] | None = None,
    framed: bool = False
) -> JsxElement {
    # `framed`: in our own footer, with its own width and a rule above; in an AI's
    # footer, inside its container and in its colours.
    shown: dict[str, any] = info or {};  # jac:ignore[W1037]
    socials: list[dict[str, str]] = (shown["socials"] or []) if shown else [];
    phone: str = (shown["phone"] or "") if shown else "";
    email: str = (shown["email"] or "") if shown else "";
    whatsapp: str = (shown["whatsapp_url"] or "") if shown else "";
    hours: str = (shown["support_hours"] or "") if shown else "";
    name: str = (shown["business_name"] or "") if shown else "";
    address: str = (shown["address"] or "") if shown else "";
    has_contact = phone or email or whatsapp or hours;
    pages: list[dict[str, str]] = policies or [];
    papers: list[dict[str, str]] = documents or [];
    if not (
        name
        or address
        or has_contact
        or len(socials) > 0
        or len(pages) > 0
        or len(papers) > 0
    ) {
        return <span className="hidden" data-testid="footer-info"/>;
    }
    frame = "mx-auto max-w-5xl border-t px-4 py-6 text-muted-foreground"
        if framed
        else "pt-6";
    # basis-full and col-span-full: a full row inside an AI footer laid out as flex or grid.
    return
        <section
            aria-label={f"About {cinema}"}
            data-testid="footer-info"
            className={"col-span-full flex w-full basis-full flex-col gap-2 text-sm "
                + frame}
        >
            <div
                className="flex flex-wrap items-center justify-between gap-x-6 gap-y-2"
            >
                {(name or address)
                    and <p
                        className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1"
                        data-testid="info-business"
                    >
                        <span className="font-medium">{name or cinema}</span>
                        {address
                            and <span className="inline-flex items-center gap-2">
                                <HugeiconsIcon
                                    icon={Location01Icon}
                                    size={18}
                                    strokeWidth={2}
                                    aria-hidden="true"
                                />
                                {address}
                            </span>}
                    </p>}{len(socials) > 0
                    and <ul
                        className="flex flex-wrap items-center"
                        data-testid="info-socials"
                        aria-label="Social media"
                    >
                        {[
                            <li key={s["network"]}>
                                <a
                                    href={s["url"]}
                                    target="_blank"
                                    rel="noreferrer"
                                    aria-label={f"{s['label']}: {s['handle']}"}
                                    style={INHERIT}
                                    className="inline-flex size-11 items-center justify-center rounded-full hover:bg-current/10"
                                >
                                    <HugeiconsIcon
                                        icon={NETWORK_ICONS[s["network"]]}
                                        size={20}
                                        strokeWidth={2}
                                        aria-hidden="true"
                                    />
                                </a>
                            </li> for s in socials
                        ]}
                    </ul>}
            </div>
            {has_contact
                and <ul
                    className="flex flex-wrap items-center gap-x-6"
                    data-testid="info-contact"
                    aria-label="Contact"
                >
                    {phone
                        and <Reach icon={Call02Icon}>
                            <a href={f"tel:{phone}"} style={INHERIT} className={LINK}>
                                {phone}
                            </a>
                        </Reach>}{email
                        and <Reach icon={Mail01Icon}>
                            <a
                                href={f"mailto:{email}"}
                                style={INHERIT}
                                className={LINK + " break-all"}
                            >
                                {email}
                            </a>
                        </Reach>}{whatsapp
                        and <Reach icon={WhatsappIcon}>
                            <a
                                href={whatsapp}
                                target="_blank"
                                rel="noreferrer"
                                style={INHERIT}
                                className={LINK}
                            >
                                WhatsApp
                            </a>
                        </Reach>}{hours
                        and <Reach icon={Clock01Icon}>
                            <span>{hours}</span>
                        </Reach>}
                </ul>}
            {len(pages) > 0
                and <ul
                    className="flex flex-wrap items-center gap-x-6"
                    data-testid="info-policies"
                    aria-label="Policies"
                >
                    {[
                        <li key={p["kind"]}>
                            <a
                                href={local_path(f"/c/{slug}/policies/{p['kind']}")}
                                style={INHERIT}
                                className={LINK}
                            >
                                {p["title"]}
                            </a>
                        </li> for p in pages
                    ]}
                </ul>}
            {len(papers) > 0
                and <ul
                    className="flex flex-wrap items-center gap-x-6"
                    data-testid="info-documents"
                    aria-label="Licences and documents"
                >
                    {[
                        <li key={d["id"]}>
                            <a
                                href={local_path(f"/c/{slug}/documents/{d['id']}")}
                                style={INHERIT}
                                className={LINK}
                            >
                                {d["title"]}
                            </a>
                        </li> for d in papers
                    ]}
                </ul>}
        </section>;
}
