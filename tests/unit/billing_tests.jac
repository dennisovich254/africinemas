"""P15.4: a statement's figures, and its PDF (ADR-0083).

- VAT is 16% of the fees, once registered, rounded half up; none before.
- A credit brought forward comes off the fees before VAT; more credit than fees owes
  nothing and carries the rest forward.
- The month before is the right one across a year's end.
- An invoice is due, overdue from the day after, paid, waived or has nothing to pay; it's
  paid in whole shillings; suspendable only more than 5 days overdue and not disputed.
- Reminders go 2 days before, on the day, 3 and 7 days after (the latest reached),
  never while disputed or once paid.
- The PDF is one: its objects' offsets in the cross-reference table are where they are,
  and a long statement goes onto more pages.
"""

import re;
import from datetime { date }
import from core.reporting.aggregates { Money }
import from core.billing.statements {
    Statement,
    figures_of,
    month_before,
    payable_of,
    payable_cents,
    status_of,
    days_overdue,
    view_of,
    VAT_BP
}
import from core.billing.collect { reminder_due }
import from core.billing.pdf { PdfLine, pdf_bytes }
import from core.billing.billing_api { kes }

def _fee(cents: int, ref: str = "R1") -> Money {
    kind = "fee" if cents >= 0 else "fee_credit";
    return Money(
        screening_id="s",
        kind=kind,
        amount_cents=cents,
        taken_at="2026-10-05T10:00:00+00:00",
        order_ref=ref
    );
}

test "VAT is 16% of the fees once registered, and a credit comes off first" {
    paid = [
        Money(
            screening_id="s",
            kind="payment",
            amount_cents=100000,
            taken_at="2026-10-05T10:00:00+00:00",
            method="mpesa",
            order_ref="R1"
        )
    ];
    (f, lines) = figures_of(paid, [_fee(7003)], 0, VAT_BP);
    assert f["vat_cents"] == 1120 and f["due_cents"] == 8123 , f;
    assert lines[0]["fee_cents"] == 7003 and lines[0]["paid_cents"] == 100000;
    (f, _) = figures_of(paid, [_fee(7003)], 0, 0);
    assert f["vat_cents"] == 0 and f["due_cents"] == 7003;
    (f, _) = figures_of(paid, [_fee(7003)], -3000, VAT_BP);
    assert f["vat_cents"] == 640 and f["due_cents"] == 4643;
    (f, _) = figures_of([], [_fee(1000), _fee(-1500)], -200, VAT_BP);
    assert f["fees_cents"] == -500 and f["due_cents"] == 0 and f["vat_cents"] == 0;
    assert f["carried_forward_cents"] == -700;
}

test "the month before, across a year's end" {
    assert month_before(date(2027, 1, 1)) == (date(2026, 12, 1), date(2026, 12, 31));
    assert month_before(date(2026, 3, 15)) == (date(2026, 2, 1), date(2026, 2, 28));
}

test "the PDF's cross-reference table points at its objects, over several pages" {
    lines = [PdfLine(text="Statement (draft) \\ test", bold=True)];
    for n in range(120) {
        lines.append(PdfLine(text=f"AB{n}", nums=[(kes(n * 101), 545.0)]));
    }
    raw = pdf_bytes(lines, "AfriCinemas AC000001");
    assert raw.startswith(b"%PDF-1.4") and raw.endswith(b"%%EOF\n");
    found = re.search(rb"startxref\n(\d+)", raw);
    assert found is not None;
    start = int(found.group(1));
    assert raw[start:start + 4] == b"xref";
    table = raw[start:].split(b"\n");
    count = int(table[1].split(b" ")[1]);
    for n in range(1, count) {
        at = int(table[2 + n][:10]);
        assert raw[at:].startswith(f"{n} 0 obj".encode()) , n;
    }
    assert b"/Count 3" in raw;
    assert kes(123456) == "KES 1,234.56" and kes(-5) == "-KES 0.05";
}

def _owed(due_cents: int, due_on: str = "2026-11-07") -> Statement {
    return Statement(
        tenant_id="t",
        month="2026-10",
        number="AC000001",
        first="2026-10-01",
        last="2026-10-31",
        timezone="Africa/Nairobi",
        issued_at="2026-11-02T06:00:00+00:00",
        issued_on="2026-11-02",
        due_on=due_on,
        currency="KES",
        figures={"due_cents": due_cents}
    );
}

test "an invoice is due, overdue from the day after, paid, waived or has nothing due" {
    s = _owed(4980);
    assert payable_of(s) == 5000
        and payable_cents(4949) == 4900
        and payable_cents(-5) == 0;
    assert status_of(s, date(2026, 11, 7)) == "due";
    assert status_of(s, date(2026, 11, 8)) == "overdue";
    assert days_overdue(s, date(2026, 11, 12)) == 5;
    assert days_overdue(s, date(2026, 11, 7)) == 0;
    assert status_of(_owed(0), date(2026, 12, 1)) == "nothing_due";
    # 49 cents rounds to nothing for M-Pesa: nothing to pay.
    assert status_of(_owed(49), date(2026, 12, 1)) == "nothing_due";
    s.dispute_outcome = "waived";
    assert status_of(s, date(2026, 12, 1)) == "waived";
    s.paid_at = "2026-11-03T10:00:00+00:00";
    assert status_of(s, date(2026, 12, 1)) == "paid";
}

test "suspendable only more than 5 days overdue, and never while disputed" {
    s = _owed(4980);
    assert not view_of(s, date(2026, 11, 12), False)["suspendable"];
    assert view_of(s, date(2026, 11, 13), False)["suspendable"];
    s.disputed_at = "2026-11-10T10:00:00+00:00";
    assert not view_of(s, date(2026, 11, 20), False)["suspendable"];
    s.dispute_resolved_at = "2026-11-21T10:00:00+00:00";
    s.dispute_outcome = "stands";
    assert view_of(s, date(2026, 11, 21), False)["suspendable"];
}

test "reminders: 2 days before, on the day, 3 and 7 days after; the latest reached" {
    s = _owed(4980);
    assert [reminder_due(s, date(2026, 11, d)) for d in [4, 5, 6, 7, 8, 10, 13, 14, 30]]
        == [
            "",
            "before",
            "before",
            "due_today",
            "due_today",
            "late_3",
            "late_3",
            "late_7",
            "late_7"
        ];
    s.disputed_at = "2026-11-08T10:00:00+00:00";
    assert reminder_due(s, date(2026, 11, 10)) == "";
    s.dispute_resolved_at = "2026-11-09T10:00:00+00:00";
    assert reminder_due(s, date(2026, 11, 10)) == "late_3";
    s.paid_at = "2026-11-10T10:00:00+00:00";
    assert reminder_due(s, date(2026, 11, 20)) == "";
}
