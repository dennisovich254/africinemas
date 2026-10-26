"""P12.14: the booking must be paid, and additions close exactly at showtime."""

import from datetime { datetime, timezone }
import from core.booking.snack_additions { addition_allowed }

test "snack additions close at the start, not a second later" {
    at = datetime(2026, 10, 26, 17, 0, tzinfo=timezone.utc);
    assert addition_allowed("confirmed", "2026-10-26T17:00:01+00:00", at);
    assert not addition_allowed("confirmed", "2026-10-26T17:00:00+00:00", at);
    assert not addition_allowed("confirmed", "2026-10-26T16:59:59+00:00", at);
    assert not addition_allowed("pending_payment", "2026-10-26T18:00:00+00:00", at);
    assert not addition_allowed("expired", "2026-10-26T18:00:00+00:00", at);
    assert not addition_allowed("confirmed", "", at);
}
