"""The strip under every storefront page (P14.3a, ADR-0066).

Drawn by StorefrontShell after everything else, whatever the cinema's design, the AI's
included, so no design can leave it out: who runs the cinema and where, how to reach
it (phone, email, WhatsApp, support hours), its social media, and "Tickets by
AfriCinemas". The policy links, public documents (14.3b) and "Report this cinema"
(14.6) join it. Every link was built on the server from what the cinema typed
(core/catalog/site_info.jac), never taken as typed.
"""

import from "@hugeicons/react" { HugeiconsIcon }
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
     LINK: str = "inline-flex min-h-11 items-center gap-2 underline-offset-4 hover:underline";

def Line(icon: any, children: any = None) -> JsxElement {  # jac:ignore[W1037]
    return
        <li className="flex items-center gap-2">
            <HugeiconsIcon icon={icon} size={18} strokeWidth={2} aria-hidden="true"/>
            {children}
        </li>;
}

def:pub PublicStrip(cinema: str, info: any) -> JsxElement {  # jac:ignore[W1037]
    shown: dict[str, any] = info or {};  # jac:ignore[W1037]
    socials: list[dict[str, str]] = (shown["socials"] or []) if shown else [];
    phone: str = (shown["phone"] or "") if shown else "";
    email: str = (shown["email"] or "") if shown else "";
    whatsapp: str = (shown["whatsapp_url"] or "") if shown else "";
    hours: str = (shown["support_hours"] or "") if shown else "";
    name: str = (shown["business_name"] or "") if shown else "";
    address: str = (shown["address"] or "") if shown else "";
    has_contact = phone or email or whatsapp or hours;
    return
        <aside
            aria-label={f"About {cinema}"}
            data-testid="public-strip"
            className="border-t bg-card text-sm text-muted-foreground"
        >
            <div
                className="mx-auto flex w-full max-w-5xl flex-col gap-4 px-4 py-6 sm:flex-row sm:flex-wrap sm:justify-between"
            >
                {(name or address)
                    and <div
                        className="flex min-w-0 flex-col gap-1"
                        data-testid="strip-business"
                    >
                        <span className="font-medium text-foreground">
                            {name or cinema}
                        </span>
                        {address
                            and <span className="flex items-start gap-2">
                                <HugeiconsIcon
                                    icon={Location01Icon}
                                    size={18}
                                    strokeWidth={2}
                                    aria-hidden="true"
                                />
                                {address}
                            </span>}
                    </div>}{has_contact
                    and <ul
                        className="flex flex-col"
                        data-testid="strip-contact"
                        aria-label="Contact"
                    >
                        {phone
                            and <Line icon={Call02Icon}>
                                <a href={f"tel:{phone}"} className={LINK}>{phone}</a>
                            </Line>}{email
                            and <Line icon={Mail01Icon}>
                                <a
                                    href={f"mailto:{email}"}
                                    className={LINK + " break-all"}
                                >
                                    {email}
                                </a>
                            </Line>}{whatsapp
                            and <Line icon={WhatsappIcon}>
                                <a
                                    href={whatsapp}
                                    target="_blank"
                                    rel="noreferrer"
                                    className={LINK}
                                >
                                    WhatsApp
                                </a>
                            </Line>}{hours
                            and <Line icon={Clock01Icon}>
                                <span>{hours}</span>
                            </Line>}
                    </ul>}{len(socials) > 0
                    and <ul
                        className="flex flex-wrap items-center gap-1"
                        data-testid="strip-socials"
                        aria-label="Social media"
                    >
                        {[
                            <li key={s["network"]}>
                                <a
                                    href={s["url"]}
                                    target="_blank"
                                    rel="noreferrer"
                                    aria-label={f"{s['label']}: {s['handle']}"}
                                    className="inline-flex size-11 items-center justify-center rounded-full hover:bg-muted"
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
            <p className="border-t px-4 py-3 text-center text-xs">
                Tickets by AfriCinemas
            </p>
        </aside>;
}
