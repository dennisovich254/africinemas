"""An amount in words, for checking a cash count before it's saved (P15.6b).

"KES 16,000" reads back as "sixteen thousand shillings": a slip of the finger (an extra
zero, a missing digit) is easier to see in words than in figures.
"""

glob ONES: list[str] = [
         "zero",
         "one",
         "two",
         "three",
         "four",
         "five",
         "six",
         "seven",
         "eight",
         "nine",
         "ten",
         "eleven",
         "twelve",
         "thirteen",
         "fourteen",
         "fifteen",
         "sixteen",
         "seventeen",
         "eighteen",
         "nineteen"
     ],
     TENS: list[str] = [
         "",
         "",
         "twenty",
         "thirty",
         "forty",
         "fifty",
         "sixty",
         "seventy",
         "eighty",
         "ninety"
     ];

def _below_thousand(n: int) -> str {
    # 0 < n < 1000.
    parts: list[str] = [];
    hundreds = int(n / 100);
    rest = n % 100;
    if hundreds > 0 {
        parts.append(ONES[hundreds] + " hundred");
    }
    if rest > 0 {
        if hundreds > 0 {
            parts.append("and");
        }
        if rest < 20 {
            parts.append(ONES[rest]);
        } else {
            tens = TENS[int(rest / 10)];
            parts.append(tens + "-" + ONES[rest % 10] if rest % 10 > 0 else tens);
        }
    }
    return " ".join(parts);
}

def:pub number_in_words(n: int) -> str {
    # 1234567 -> "one million two hundred and thirty-four thousand five hundred and
    # sixty-seven".
    if n == 0 {
        return "zero";
    }
    parts: list[str] = [];
    left = n;
    for (size, name) in [
        (1000000000, "billion"),
        (1000000, "million"),
        (1000, "thousand")
    ] {
        if left >= size {
            parts.append(_below_thousand(int(left / size)) + " " + name);
            left = left % size;
        }
    }
    if left > 0 {
        if len(parts) > 0 and left < 100 {
            parts.append("and");
        }
        parts.append(_below_thousand(left));
    }
    return " ".join(parts);
}

def:pub shillings_in_words(cents: int) -> str {
    # 1600050 -> "sixteen thousand shillings and fifty cents".
    shillings = int(cents / 100);
    rest = cents % 100;
    said = number_in_words(shillings)
        + (" shilling" if shillings == 1 else " shillings");
    if rest > 0 {
        said += " and " + number_in_words(rest) + (" cent" if rest == 1 else " cents");
    }
    return said;
}
