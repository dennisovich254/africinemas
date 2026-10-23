"""Keeping the support chat up to date without a refresh (P13.5a).

Jac's WebSockets can't send a message to one cinema's staff (JI-054), so pages that
show help requests ask again every few seconds while they're on screen: a chat every
CHAT_MS, lists and the sidebar's counts every LIST_MS. A tab in the background asks
nothing, and asks at once when it's back. Each request is the caller's own, as any
page's is, so nothing reaches anyone it isn't for.
"""

import from react { useEffect, useState }
import from core.support.requests {
    support_requests,  # jac:ignore[W2037] authenticated endpoint
    platform_support_requests  # jac:ignore[W2037]
}

glob:pub CHAT_MS: int = 5000,
     LIST_MS: int = 30000;

def:pub use_every(ms: int, work: any, keys: list[any]) {  # jac:ignore[W1037]
    # Runs `work` every `ms` while the page is visible, and at once when it becomes
    # visible again; not at mount (the page loads its data itself).
    def start -> any {  # jac:ignore[W1037]
        doc: any = document;  # jac:ignore[W1037,W2001]
        win: any = window;  # jac:ignore[W1037,W2001]
        def tick {
            if doc.visibilityState == "visible" {
                work();
            }
        }
        def back {
            if doc.visibilityState == "visible" {
                work();
            }
        }
        timer: any = win.setInterval(tick, ms);  # jac:ignore[W1037,W6001] client-only
        doc.addEventListener("visibilitychange", back);
        def stop {
            win.clearInterval(timer);  # jac:ignore[W6001]
            doc.removeEventListener("visibilitychange", back);
        }
        return stop;
    }
    useEffect(start, keys);
}

def:pub use_waiting_for_cinema(slug: str, enabled: bool) -> int {
    # How many of the cinema's requests AfriCinemas has answered (its turn), for the
    # back office's Help link.
    [count, set_count] = useState(0);
    async def load {
        if not enabled {
            return;
        }
        try {
            answer: any = await support_requests(slug);  # jac:ignore[W1037,W2037]
            if answer["ok"] {
                rows: list[dict[str, any]] = answer["requests"];  # jac:ignore[W1037]
                set_count(
                    len(
                        [
                            r
                            for r in rows
                            if r["status"] == "waiting"
                        ]
                    )
                );
            }
        } except Exception as e {
            console.warn("support_requests failed", e);
        }
    }
    def first {
        load();
    }
    useEffect(first, [slug, enabled]);
    use_every(LIST_MS, load, [slug, enabled]);
    return count;
}

def:pub use_open_requests(enabled: bool) -> int {
    # How many help requests wait on AfriCinemas, for the console's Support link.
    [count, set_count] = useState(0);
    async def load {
        if not enabled {
            return;
        }
        try {
            answer: any = await platform_support_requests("open");  # jac:ignore[W1037,W2037]
            if answer["ok"] {
                set_count(len(answer["requests"]));
            }
        } except Exception as e {
            console.warn("platform_support_requests failed", e);
        }
    }
    def first {
        load();
    }
    useEffect(first, [enabled]);
    use_every(LIST_MS, load, [enabled]);
    return count;
}
