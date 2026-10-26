"""P12.13: small rules shared by catalogue, ordering and checkout."""

import from core.catalog.formats { normalize_format, glasses_for_order }

test "movie and showtime formats are only 2D or 3D" {
    assert normalize_format("2d") == "2D";
    assert normalize_format(" 3D ") == "3D";
    assert normalize_format("", "3D") == "3D";
    with testraises(ValueError) {
        normalize_format("IMAX");
    }
}

test "glasses are an explicit per-seat choice for a 3D order" {
    assert glasses_for_order("3D", ["A2"], ["A1", "A2"]) == ["A2"];
    assert glasses_for_order("3D", [], ["A1", "A2"]) == [];
    with testraises(ValueError) {
        glasses_for_order("2D", ["A1"], ["A1"]);
    }
    with testraises(ValueError) {
        glasses_for_order("3D", ["A3"], ["A1", "A2"]);
    }
}
