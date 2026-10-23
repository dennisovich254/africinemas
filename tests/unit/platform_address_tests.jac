"""P13.1b.b: the platform's own address, "admin." in front of the main site's."""

import from core.platform.accounts { platform_address }

test "the platform's address is admin. in front of the main site's" {
    assert platform_address("https://africinemas.co.ke")
        == "https://admin.africinemas.co.ke";
    assert platform_address("https://www.africinemas.co.ke/")
        == "https://admin.africinemas.co.ke";
    assert platform_address("http://localhost:8000") == "http://admin.localhost:8000";
}
