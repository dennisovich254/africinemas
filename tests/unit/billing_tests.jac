"""P15.4: a statement's figures, and its PDF (ADR-0083).

- VAT is 16% of the fees, once registered, rounded half up; none before.
- A credit brought forward comes off the fees before VAT; more credit than fees owes
  nothing and carries the rest forward.
- The month before is the right one across a year's end.
- The PDF is one: its objects' offsets in the cross-reference table are where they are,
  and a long statement goes onto more pages.
"""

import re;
import from datetime { date }
import from core.reporting.aggregates { Money }
import from core.billing.statements { figures_of, month_before, VAT_BP }
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
