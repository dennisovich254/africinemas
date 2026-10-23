"""P13.1b.b: the platform's own address, "admin." in front of the main site's."""

import os;
import from core.platform.accounts { platform_address }

test "the platform's address is admin. in front of the main site's" {
    assert platform_address("https://africinemas.co.ke")
        == "https://admin.africinemas.co.ke";
    assert platform_address("https://www.africinemas.co.ke/")
        == "https://admin.africinemas.co.ke";
    assert platform_address("http://localhost:8000") == "http://admin.localhost:8000";
}

test "AFRICINEMAS_PLATFORM_URL names the platform's address outright" {
    # The main site's address may be a tunnel, which serves that one address only.
    os.environ["AFRICINEMAS_PLATFORM_URL"] = "http://admin.localhost:8000/";
    os.environ["AFRICINEMAS_PUBLIC_URL"] = "https://tunnel.trycloudflare.com";
    try {
        assert platform_address() == "http://admin.localhost:8000";
    } finally {
        os.environ.pop("AFRICINEMAS_PLATFORM_URL", None);
        os.environ.pop("AFRICINEMAS_PUBLIC_URL", None);
    }
}
