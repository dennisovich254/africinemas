"""P8.1: a movie's trailer link (core/catalog/trailer.jac).

Only https YouTube and Vimeo links are kept, in one canonical form, with the embed URL
the chat and the storefront play them from (YouTube's no-cookie domain). Anything else
(another site, plain http, a script URL, a look-alike domain) is refused; an empty link
clears the trailer.
"""

import from core.catalog.trailer { TrailerRejected, clean_trailer, trailer_embed }

glob ID: str = "dQw4w9WgXcQ";

test "YouTube links in their usual shapes become one canonical link" {
    for link in [
        f"https://www.youtube.com/watch?v={ID}",
        f"https://youtube.com/watch?v={ID}&t=42s",
        f"https://m.youtube.com/watch?v={ID}",
        f"https://youtu.be/{ID}",
        f"https://youtu.be/{ID}?si=abc",
        f"https://www.youtube.com/embed/{ID}",
        f"https://www.youtube.com/shorts/{ID}",
        f"  https://www.youtube.com/watch?v={ID}  "
    ] {
        assert clean_trailer(link) == f"https://www.youtube.com/watch?v={ID}" , link;
    }
    assert trailer_embed(f"https://www.youtube.com/watch?v={ID}")
        == f"https://www.youtube-nocookie.com/embed/{ID}";
}

test "Vimeo links become one canonical link" {
    for link in [
        "https://vimeo.com/76979871",
        "https://www.vimeo.com/76979871",
        "https://player.vimeo.com/video/76979871"
    ] {
        assert clean_trailer(link) == "https://vimeo.com/76979871" , link;
    }
    assert trailer_embed("https://vimeo.com/76979871")
        == "https://player.vimeo.com/video/76979871";
}

test "an empty link clears the trailer" {
    assert clean_trailer("") == "" and clean_trailer("   ") == "";
    assert trailer_embed("") == "";
}

test "anything else is refused" {
    for link in [
        f"http://www.youtube.com/watch?v={ID}",
        "javascript:alert(1)",
        "https://example.com/trailer.mp4",
        f"https://youtube.com.evil.example/watch?v={ID}",
        f"https://evil.example/https://youtu.be/{ID}",
        "https://www.youtube.com/watch?v=",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/watch?v=<script>x</sc",
        "https://vimeo.com/not-a-number",
        "https://user:pass@youtube.com/watch?v=dQw4w9WgXcQ",
        "ftp://vimeo.com/76979871",
        f"https://www.youtube.com/watch?v={ID}%0A",
        "https://vimeo.com/76979871%0A",
        "x" * 600
    ] {
        try {
            clean_trailer(link);
            assert False , f"accepted {link}";
        } except TrailerRejected {}
    }
}
