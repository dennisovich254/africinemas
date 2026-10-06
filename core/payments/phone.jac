"""M-Pesa phone numbers (P5.1): what a customer types, in the form M-Pesa wants.

Kenyan mobile numbers are 2547XXXXXXXX or 2541XXXXXXXX (12 digits). Customers write
them as 07.., 01.., +254.., 254.. or without the leading 0, with spaces or dashes.
"""

import re;

class InvalidPhone(ValueError) {}

def msisdn(text: str) -> str {
    # "0712 345 678" -> "254712345678"; raises InvalidPhone for anything else.
    digits = re.sub(r"[\s\-]", "", text or "");
    if digits.startswith("+") {
        digits = digits[1:];
    }
    if not digits.isdigit() {
        raise InvalidPhone("Enter an M-Pesa number, like 0712 345 678.");
    }
    if digits.startswith("0") and len(digits) == 10 {
        digits = "254" + digits[1:];
    } elif len(digits) == 9 {
        digits = "254" + digits;
    }
    if not re.fullmatch(r"254[17]\d{8}", digits) {
        raise InvalidPhone("Enter an M-Pesa number, like 0712 345 678.");
    }
    return digits;
}
