"""P12.4: stock rules (core/snacks/stock.jac), as pure logic. Design guide §8.

- An adjustment has a reason. Received adds (1 or more); damaged takes away (1 or more,
  not more than on hand); a count correction sets the counted total (0 or more); other
  changes by any non-zero amount that doesn't go below zero. At most 100,000 at a time.
- Available = on hand − reserved (never shown below zero). A variant is "out" with
  nothing available, "low" at or under its threshold, else "ok".
- At zero, a tracked variant either stops selling ("unavailable", for bottles and
  packets) or keeps selling ("allow", for snacks made to order). An untracked variant
  always sells.
"""

import from core.snacks.stock {
    check_adjustment,
    check_rules,
    stock_status,
    available_of,
    stock_allows,
    REASONS
}

test "each reason changes stock its own way" {
    assert REASONS == ["received", "damaged", "count", "other"];
    assert check_adjustment("received", 50, 0) == (50, "");
    assert check_adjustment("damaged", 3, 50) == (-3, "");
    assert check_adjustment("count", 40, 47) == (-7, "");
    assert check_adjustment("count", 60, 47) == (13, "");
    assert check_adjustment("other", -2, 10) == (-2, "");
    assert check_adjustment("other", 5, 10) == (5, "");
}

test "an adjustment that makes no sense is refused with a reason" {
    for (reason, quantity, on_hand) in [
        ("received", 0, 0),
        ("received", -5, 0),
        ("damaged", 0, 10),
        ("damaged", 11, 10),
        ("count", -1, 10),
        ("other", 0, 10),
        ("other", -11, 10),
        ("received", 100001, 0),
        ("stolen", 1, 10),
        ("received", "5", 0)
    ] {
        (delta, problem) = check_adjustment(reason, quantity, on_hand);
        assert delta == 0 and problem , (reason, quantity, on_hand);
    }
}

test "available, low and out" {
    assert available_of(10, 3) == 7;
    assert available_of(2, 3) == 0;
    assert stock_status(10, 0, 5) == "ok";
    assert stock_status(10, 5, 5) == "low";
    assert stock_status(3, 3, 0) == "out";
    assert stock_status(0, 0, 0) == "out";
}

test "at zero a tracked variant stops or keeps selling; untracked always sells" {
    assert stock_allows(False, 0, "unavailable", 1);
    assert stock_allows(True, 2, "unavailable", 2);
    assert not stock_allows(True, 1, "unavailable", 2);
    assert stock_allows(True, 0, "allow", 3);
}

test "stock rules: a threshold of 0 to 100,000 and an at-zero choice" {
    assert check_rules(10, "unavailable") == "";
    assert check_rules(0, "allow") == "";
    for (low, at_zero) in [
        (-1, "allow"),
        (100001, "allow"),
        (5, "maybe"),
        ("5", "allow")
    ] {
        assert check_rules(low, at_zero) , (low, at_zero);
    }
}
