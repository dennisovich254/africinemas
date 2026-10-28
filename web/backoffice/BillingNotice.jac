"""The banner above every back-office page for an overdue invoice or a suspension
(P15.5, ADR-0084).

Suspended: everyone on the team is told why, and that the storefront is down and takes
no bookings or payments; staff who can pay get the link to Billing, others are asked to
tell the owner. An invoice overdue: staff who can pay are told which, and how late.
"""

import from react { useState, useEffect }
import from core.billing.billing_api { billing_notice }  # jac:ignore[W2037] authenticated endpoint
import from .nav { section_path }
import from ..shell.AppLink { AppLink }

glob LINK: str = "inline-flex min-h-11 items-center rounded-md bg-primary px-4 text-sm font-medium text-primary-foreground";

def:pub BillingNotice(slug: str, section: str) -> JsxElement {
    [notice, set_notice] = useState(None);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await billing_notice(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("billing_notice failed", e);
        }
        if got is not None and got["ok"] {
            set_notice(got);
        }
    }

    def start {
        load();
    }
    useEffect(start, [slug, section]);

    shown: dict[str, any] | None = notice;  # jac:ignore[W1037]
    if shown is None {
        return <span className="hidden"/>;
    }
    late: list[dict[str, any]] = shown["overdue"];  # jac:ignore[W1037]
    may_pay: bool = bool(shown["may_pay"]);
    if shown["suspended"] {
        return
            <div
                role="alert"
                data-testid="suspended-notice"
                className="flex flex-wrap items-center gap-3 rounded-xl bg-destructive/10 px-4 py-3 ring-1 ring-destructive/30"
            >
                <p className="min-w-0 flex-1 text-sm">
                    {"AfriCinemas has suspended this cinema: its storefront is down and it can't take bookings or payments. "
                        + (shown["suspended_reason"] or "")
                        + (
                            " Pay what's overdue to have it reinstated."
                                if may_pay
                                else " Ask the owner to pay what's overdue."
                        )}
                </p>
                {may_pay
                    and section != "billing"
                    and <AppLink to={section_path(slug, "billing")} className={LINK}>
                        Open Billing
                    </AppLink>}
            </div>;
    }
    if not may_pay or len(late) == 0 or section == "billing" {
        return <span className="hidden"/>;
    }
    first: dict[str, any] = late[0];  # jac:ignore[W1037]
    days: int = int(first["days"]);
    return
        <div
            role="region"
            aria-label="Overdue invoice"
            data-testid="overdue-notice"
            className="flex flex-wrap items-center gap-3 rounded-xl bg-card px-4 py-3 ring-1 ring-destructive/30"
        >
            <p className="min-w-0 flex-1 text-sm">
                {f"Invoice {first['number']} is overdue by {days} day"
                    + ("" if days == 1 else "s")
                    + ". Pay it in Billing, or tell us there if something on it is wrong."}
            </p>
            <AppLink to={section_path(slug, "billing")} className={LINK}>
                Open Billing
            </AppLink>
        </div>;
}
