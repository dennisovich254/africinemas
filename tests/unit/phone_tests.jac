"""P5.1: M-Pesa phone numbers (core/payments/phone.jac).

Customers type their number as they know it (0712 345 678, +254 712 345 678,
254712345678); M-Pesa wants 2547XXXXXXXX or 2541XXXXXXXX. Anything else is refused.
"""

import from core.payments.phone { msisdn, InvalidPhone }

def _refused(text: str) -> bool {
    try {
        msisdn(text);
    } except InvalidPhone {
        return True;
    }
    return False;
}

test "the usual ways of writing a Kenyan mobile number become one form" {
    for typed in [
        "0712345678",
        "0712 345 678",
        "+254712345678",
        "254712345678",
        "+254 712-345-678",
        "712345678"
    ] {
        assert msisdn(typed) == "254712345678" , typed;
    }
    assert msisdn("0110123456") == "254110123456";
}

test "numbers that aren't Kenyan mobiles are refused" {
    for typed in [
        "",
        "12345",
        "0202345678",
        "+255712345678",
        "07123456789",
        "07a2345678"
    ] {
        assert _refused(typed) , typed;
    }
}
