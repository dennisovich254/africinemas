"""P13.1b: the three sites' addresses (core/site.jac).

Under AFRICINEMAS_SITE_DOMAIN: the main site on the domain, the platform on admin., each
cinema's storefront on its slug; any other address (a tunnel) is every site, as before
the split. Links sent out use the cinema's own address unless our public address is a
tunnel, which serves only itself.
"""

import os;
import from core.site {
    site_domain,
    site_scheme,
    platform_address,
    storefront_address,
    site_of_host
}

def _with(domain: str, public: str) {
    os.environ["AFRICINEMAS_SITE_DOMAIN"] = domain;
    os.environ["AFRICINEMAS_PUBLIC_URL"] = public;
}

def _clear {
    os.environ.pop("AFRICINEMAS_SITE_DOMAIN", None);
    os.environ.pop("AFRICINEMAS_PUBLIC_URL", None);
}

test "production: every site under the domain, links on the cinema's own address" {
    _with("", "https://www.africinemas.co.ke");
    try {
        assert site_domain() == "africinemas.co.ke";
        assert site_scheme() == "https";
        assert platform_address() == "https://admin.africinemas.co.ke";
        assert storefront_address("anga", "/tickets/abc")
            == "https://anga.africinemas.co.ke/tickets/abc";
        assert storefront_address("anga") == "https://anga.africinemas.co.ke/";
        assert site_of_host("africinemas.co.ke")["site"] == "main";
        assert site_of_host("www.africinemas.co.ke")["site"] == "main";
        assert site_of_host("ADMIN.africinemas.co.ke")["site"] == "platform";
        assert site_of_host("evil.example.com")["site"] == "any";
        # Two labels deep is no cinema's.
        assert site_of_host("a.b.africinemas.co.ke")["site"] == "none";
    } finally {
        _clear();
    }
}

test "development behind a tunnel: localhost is the domain, links use the tunnel" {
    _with("localhost:8000", "https://quick.trycloudflare.com");
    try {
        assert site_scheme() == "http";
        assert platform_address() == "http://admin.localhost:8000";
        assert storefront_address("anga", "/tickets/abc")
            == "https://quick.trycloudflare.com/c/anga/tickets/abc";
        assert site_of_host("localhost:8000")["site"] == "main";
        assert site_of_host("admin.localhost:8000")["site"] == "platform";
        # The tunnel serves every site, under /c/<slug>, as before.
        assert site_of_host("quick.trycloudflare.com")["site"] == "any";
        assert site_of_host("127.0.0.1:8000")["site"] == "any";
    } finally {
        _clear();
    }
}
