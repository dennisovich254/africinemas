"""Presentation formats and per-ticket 3D-glasses choices (P12.13)."""

glob FORMATS: list[str] = ["2D", "3D"];

def normalize_format(value: str, fallback: str = "2D") -> str {
    cleaned = str(value or fallback).strip().upper();
    if cleaned not in FORMATS {
        raise ValueError("Choose 2D or 3D.");
    }
    return cleaned;
}

def glasses_for_order(
    presentation: str, requested: list[str], sold_seats: list[str]
) -> list[str] {
    picked = [str(x).strip().upper() for x in requested];
    if len(picked) != len(set(picked)) or any(x not in sold_seats for x in picked) {
        raise ValueError("Choose glasses only for tickets in this order.");
    }
    if picked and normalize_format(presentation) != "3D" {
        raise ValueError("3D glasses are only available for a 3D showtime.");
    }
    return sorted(picked);
}
