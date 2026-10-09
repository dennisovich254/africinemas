"""A showtime's poster or backdrop for staff pages (P7.4): the home page's hero and
cards, the box office's showtime cards.

It loads from showtime_art (staff with a shift who may read the showtime; the cinema
needn't be public yet). Decorative: the title is always written beside it. An empty
frame of the same size while it loads or when the movie has none.
"""

import from react { useState, useEffect }
import from core.reporting.staff_home { showtime_art }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)

def:pub ShowtimeArt(
    slug: str, screening_id: str, kind: str, available: bool, className: str = ""
) -> JsxElement {
    # A showtime's poster or backdrop from showtime_art (staff-only; the cinema needn't
    # be public yet). Decorative: the title is always written beside it. An empty frame
    # of the same size while it loads or when the movie has none.
    [src, set_src] = useState("");

    async def load {
        set_src("");
        if not available {
            return;
        }
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await showtime_art(slug, screening_id, kind);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("showtime_art failed", e);
            return;
        }
        if got["ok"] {
            set_src(got["image"]);
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, screening_id, kind, available]);

    return
        <div aria-hidden="true" className={f"overflow-hidden bg-white/5 {className}"}>
            {src
                and <img
                    src={src}
                    alt=""
                    loading="lazy"
                    className="h-full w-full object-cover"
                />}
        </div>;
}
