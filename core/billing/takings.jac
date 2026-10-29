"""AfriCinemas' own takings (P15.6, ADR-0085), for the console's overview.

Per month and per cinema:
- **earned**: the fees charged less those credited back (core/payments/fees.jac), by
  the cinema's local month the entry was made in;
- **invoiced**: what its statement for that month asks to be paid (payable_of);
- **paid**, **overdue** and **waived**: the part of what was invoiced in each state.

The platform's totals are the sums of the cinemas', so what's invoiced is exactly the
sum of the invoices.
"""

import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from core.tenancy.models { Tenant }
import from core.catalog.storefront_api { cinema_timezone }
import from core.reporting.report_api { cinema_records }
import from core.billing.statements {
    statements_of,
    payable_of,
    status_of,
    local_today
}

glob FIELDS: list[str] = [
         "earned_cents",
         "invoiced_cents",
         "paid_cents",
         "overdue_cents",
         "waived_cents"
     ];

def _blank(month: str) -> dict[str, any] {  # jac:ignore[W1037]
    row: dict[str, any] = {"month": month};  # jac:ignore[W1037]
    for f in FIELDS {
        row[f] = 0;
    }
    return row;
}

def cinema_takings(cinema: Tenant) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The cinema's months, newest first.
    zone = ZoneInfo(cinema_timezone(cinema));
    months: dict[str, dict[str, any]] = {};  # jac:ignore[W1037]
    for m in cinema_records(cinema).fees {
        month = datetime.fromisoformat(m.taken_at).astimezone(zone).date().isoformat()[:7];
        months.setdefault(month, _blank(month));
        months[month]["earned_cents"] = months[month]["earned_cents"] + m.amount_cents;
    }
    today = local_today(cinema);
    for s in statements_of(cinema) {
        months.setdefault(s.month, _blank(s.month));
        row = months[s.month];
        owed = payable_of(s);
        row["invoiced_cents"] = row["invoiced_cents"] + owed;
        status = status_of(s, today);
        if status == "paid" {
            row["paid_cents"] = row["paid_cents"] + owed;
        } elif status == "overdue" {
            row["overdue_cents"] = row["overdue_cents"] + owed;
        } elif status == "waived" {
            row["waived_cents"] = row["waived_cents"] + owed;
        }
    }
    return sorted(
        months.values(),
        key=lambda (r: dict[str, any]) -> str { return str(r["month"]); },  # jac:ignore[W1037]
        reverse=True
    );
}

def platform_takings(cinemas: list[Tenant]) -> dict[str, any] {  # jac:ignore[W1037]
    by_month: dict[str, dict[str, any]] = {};  # jac:ignore[W1037]
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for cinema in cinemas {
        mine = cinema_takings(cinema);
        if len(mine) == 0 {
            continue;
        }
        total = _blank("");
        for r in mine {
            month = str(r["month"]);
            by_month.setdefault(month, _blank(month));
            for f in FIELDS {
                by_month[month][f] = by_month[month][f] + r[f];
                total[f] = total[f] + r[f];
            }
        }
        rows.append(
            {
                "name": cinema.name,
                "slug": cinema.slug,
                "months": mine,
                ** {f: total[f] for f in FIELDS}
            }
        );
    }
    totals = _blank("");
    for r in by_month.values() {
        for f in FIELDS {
            totals[f] = totals[f] + r[f];
        }
    }
    return {
        "months": sorted(
            by_month.values(),
            key=lambda (r: dict[str, any]) -> str { return str(r["month"]); },  # jac:ignore[W1037]
            reverse=True
        ),
        "cinemas": sorted(
            rows,
            key=lambda (r: dict[str, any]) -> str { return str(r["name"]); }  # jac:ignore[W1037]
        ),
        "totals": {f: totals[f] for f in FIELDS}
    };
}
