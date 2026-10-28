"""How billing writes money and days (P15.4, P15.5): "KES 1,234.56", "7 Nov 2026"."""

import from datetime { date }

glob MONTHS: list[str] = [
         "January",
         "February",
         "March",
         "April",
         "May",
         "June",
         "July",
         "August",
         "September",
         "October",
         "November",
         "December"
     ];

def kes(cents: int) -> str {
    sign = "-" if cents < 0 else "";
    return f"{sign}KES {abs(cents) // 100:,}.{abs(cents) % 100:02d}";
}

def day_label(iso: str) -> str {
    found = date.fromisoformat(iso[:10]);
    return f"{found.day} {MONTHS[found.month - 1][:3]} {found.year}";
}

def month_label(month: str) -> str {
    return f"{MONTHS[int(month[5:7]) - 1]} {month[:4]}";
}
