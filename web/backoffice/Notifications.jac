"""The back office's notifications (owner, 2026-11-01; core/notify/notices.jac).

use_notices loads the member's notices and keeps them fresh (every LIST_MS while the
page is visible); its unread counts by section badge the sidebar. The bell, in the top
bar of every section and beside View storefront on the Overview, lists them: opening one
goes to its section and marks it read; Mark all as read clears them.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Notification01Icon }
import from ...components.ui.button { Button }
import from ...components.ui.popover { Popover, PopoverTrigger, PopoverContent }
import from core.notify.notices {
    my_notices,  # jac:ignore[W2037] authenticated endpoint
    read_notices  # jac:ignore[W2037] authenticated endpoint
}
import from ..support.live { use_every, LIST_MS }
import from .nav { section_path }

glob EMPTY: dict[str, any] = {"notices": [], "unread": 0, "sections": {}};  # jac:ignore[W1037]

def:pub use_notices(slug: str, enabled: bool) -> list[any] {  # jac:ignore[W1037]
    # [the notices, mark(ids, section, everything)]: mark updates them from the answer.
    [state, set_state] = useState(EMPTY);

    def keep(got: any) {  # jac:ignore[W1037]
        if got is not None and got["ok"] {
            set_state(got);
        }
    }

    async def load {
        if not enabled {
            return;
        }
        try {
            keep(await my_notices(slug));  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("my_notices failed", e);
        }
    }

    async def mark(ids: list[str], section: str, everything: bool) {
        try {
            keep(await read_notices(slug, ids, section, everything));  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("read_notices failed", e);
        }
    }

    def first {
        load();
    }
    useEffect(first, [slug, enabled]);
    use_every(LIST_MS, load, [slug, enabled]);
    return [state, mark];
}

def ago(stamp: str) -> str {
    # "Just now", "5 min ago", "3 h ago", "2 days ago".
    seconds = (Date.now() - new(Date, stamp).getTime()) / 1000;  # jac:ignore[W2001]
    if seconds < 60 {
        return "Just now";
    }
    if seconds < 3600 {
        return f"{int(seconds / 60)} min ago";
    }
    if seconds < 86400 {
        return f"{int(seconds / 3600)} h ago";
    }
    days = int(seconds / 86400);
    return "1 day ago" if days == 1 else f"{days} days ago";
}

def:pub NotificationsBell(
    slug: str,
    notices: any,  # jac:ignore[W1037] use_notices' state
    mark: any  # jac:ignore[W1037] use_notices' mark
) -> JsxElement {
    nav = useNavigate();
    [open, set_open] = useState(False);
    rows: list[dict[str, any]] = notices["notices"];  # jac:ignore[W1037]
    unread: int = int(notices["unread"]);

    def go(n: dict[str, any]) {  # jac:ignore[W1037]
        set_open(False);
        if not n["read"] {
            mark([n["id"]], "", False);
        }
        nav(section_path(slug, n["section"]));
    }

    return
        <Popover open={open} onOpenChange={set_open}>
            <PopoverTrigger asChild={True}>
                <Button
                    variant="ghost"
                    size="icon"
                    className="relative size-11 rounded-full bg-card ring-1 ring-foreground/10 hover:bg-muted"
                    data-testid="notifications-bell"
                    aria-label={f"Notifications, {unread} unread"
                        if unread
                        else "Notifications"}
                >
                    <HugeiconsIcon
                        icon={Notification01Icon}
                        strokeWidth={2}
                        aria-hidden="true"
                    />
                    {unread > 0
                        and <span
                            aria-hidden="true"
                            data-testid="notifications-count"
                            className="absolute -top-1 -right-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-primary px-1 text-[11px] font-semibold leading-none text-primary-foreground tabular-nums ring-2 ring-background"
                        >
                            {str(unread) if unread < 100 else "99+"}
                        </span>}
                </Button>
            </PopoverTrigger>
            <PopoverContent data-testid="notifications-panel">
                <div
                    className="flex items-center justify-between gap-2 border-b px-4 py-3"
                >
                    <h2 className="text-base font-semibold">Notifications</h2>
                    {unread > 0
                        and <Button
                            variant="ghost"
                            className="min-h-11 px-3"
                            data-testid="notifications-read-all"
                            onClick={lambda { mark([], "", True); }}
                        >
                            Mark all as read
                        </Button>}
                </div>
                {len(rows) == 0
                    and <p className="px-4 py-6 text-center text-muted-foreground">
                        Nothing new.
                    </p>}
                <ul className="max-h-[60svh] divide-y overflow-y-auto">
                    {[
                        <li key={n["id"]}>
                            <button
                                type="button"
                                data-testid="notification"
                                data-read={"true" if n["read"] else "false"}
                                onClick={lambda { go(n); }}
                                className="flex w-full gap-3 px-4 py-3 text-left hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring"
                            >
                                <span
                                    aria-hidden="true"
                                    className={"mt-1.5 size-2 shrink-0 rounded-full "
                                        + (
                                            "bg-transparent"
                                                if n["read"]
                                                else "bg-primary"
                                        )}
                                />
                                <span className="flex min-w-0 flex-col gap-0.5">
                                    <span
                                        className={"font-medium"
                                            if not n["read"]
                                            else ""}
                                    >
                                        {n["title"]}{not n["read"]
                                            and <span className="sr-only">
                                                (unread)
                                            </span>}
                                    </span>
                                    {n["body"]
                                        and <span
                                            className="line-clamp-2 text-muted-foreground"
                                        >
                                            {n["body"]}
                                        </span>}
                                    <span className="text-xs text-muted-foreground">
                                        {ago(n["created_at"])}
                                    </span>
                                </span>
                            </button>
                        </li> for n in rows
                    ]}
                </ul>
            </PopoverContent>
        </Popover>;
}
