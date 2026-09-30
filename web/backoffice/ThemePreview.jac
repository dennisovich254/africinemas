"""A small storefront drawn with the theme being edited (P3.8b), in light or dark.

It uses the draft's colours directly (checked #RRGGBB values only; see branding_model),
so owners see every change before saving. Fonts and radius come from the server's
allowlists (get_branding's options).
"""

def _seat(bg: str, border: str, fg: str, text: str, label: str) -> JsxElement {
    return
        <span
            role="img"
            aria-label={label}
            className="grid size-7 place-items-center rounded-t-md rounded-b-sm border-2 text-xs"
            style={{"background": bg, "borderColor": border, "color": fg}}
        >
            {text}
        </span>;
}

def:pub ThemePreview(
    theme: dict[str, any],  # jac:ignore[W1037]
    mode: str,
    options: dict[str, any],  # jac:ignore[W1037]
    logo: str = "",
    cinema: str = ""
) -> JsxElement {
    t: dict[str, str] = theme[mode];
    stacks: dict[str, str] = options["font_stacks"];
    radius: str = options["radius_rem"][theme["radius"]];
    display = stacks[theme["display_font"]];
    body = stacks[theme["body_font"]];
    card = {
        "background": t["surface"],
        "borderColor": t["border"],
        "borderRadius": radius
    };
    return
        <div
            data-testid="theme-preview"
            data-mode={mode}
            role="group"
            aria-label={f"Storefront preview, {mode} mode"}
            className="flex flex-col gap-4 overflow-hidden rounded-xl border p-4"
            style={{
                "background": t["background"],
                "color": t["ink"],
                "fontFamily": body
            }}
        >
            <div className="flex items-center justify-between gap-3">
                {logo and <img src={logo} alt="" className="h-8 w-auto max-w-[60%]"/>}
                {not logo
                    and <span
                        className="text-2xl leading-none"
                        style={{"fontFamily": display}}
                    >
                        {cinema or "Your cinema"}
                    </span>}
                <span className="text-xs" style={{"color": t["muted"]}}>Westgate</span>
            </div>
            <div className="flex flex-col gap-3 border p-3" style={card}>
                <span className="text-2xl leading-none" style={{"fontFamily": display}}>
                    Nairobi Nights
                </span>
                <span className="text-sm" style={{"color": t["muted"]}}>
                    Drama · 1 h 58 min · PG
                </span>
                <div className="flex flex-wrap gap-2">
                    <span
                        className="border px-3 py-1 text-sm font-medium"
                        style={{
                            "background": t["surface"],
                            "borderColor": t["border"],
                            "borderRadius": radius
                        }}
                    >
                        14:30
                    </span>
                    <span
                        className="border px-3 py-1 text-sm font-medium"
                        style={{
                            "background": t["accent"],
                            "borderColor": t["accent"],
                            "color": t["on_accent"],
                            "borderRadius": radius
                        }}
                    >
                        18:15
                    </span>
                </div>
                <div className="flex flex-wrap items-center gap-1.5">
                    {_seat(
                        "transparent",
                        t["seat_available"],
                        t["muted"],
                        "",
                        "Available seat"
                    )}{_seat(
                        t["seat_selected"],
                        t["seat_selected"],
                        t["on_seat_selected"],
                        "✓",
                        "Selected seat"
                    )}{_seat(
                        t["seat_held"], t["seat_held"], t["ink"], "", "Held seat"
                    )}{_seat(
                        t["seat_sold"], t["seat_sold"], t["muted"], "×", "Sold seat"
                    )}
                </div>
                <span className="text-sm font-medium" style={{"color": t["link"]}}>
                    See all showtimes
                </span>
            </div>
            <span
                data-testid="preview-button"
                className="grid min-h-11 place-items-center px-4 font-semibold"
                style={{
                    "background": t["accent"],
                    "color": t["on_accent"],
                    "borderRadius": radius
                }}
            >
                Pay with M-Pesa
            </span>
        </div>;
}
