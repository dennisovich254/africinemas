"""The written page, reviewed from its own screenshots (ADR-0050).

No browser and no network: the screenshots (`shoot`) and Claude (`ask`) are replaced.
The page is filled like the storefront fills it; a review that can't run, or answers
with an incomplete template, keeps the page as written.
"""

import io;
import from PIL { Image }
import core.theming.pagereview as pagereview;
import from core.ai.claude { ClaudeFailed }
import from core.theming.pagecode { sanitize }
import from core.theming.pagereview {
    ReviewSkipped,
    filled_document,
    programme_lists,
    sample_lists,
    review_page
}

glob FIXTURE: str = "tests/fixtures/ai_storefront.html";

def _fixture -> str {
    with open(FIXTURE) as f {
        return f.read();
    }
}

def _page -> dict[str, str] {
    made = sanitize(_fixture());
    return {"html": made["html"], "css": made["css"], "model": "claude-opus-5-5"};
}

def _logo -> bytes {
    out = io.BytesIO();
    Image.new("RGBA", (120, 60), (201, 164, 58, 255)).save(out, "WEBP");
    return out.getvalue();
}

test "the page is filled like the storefront fills it, posters and figures included" {
    lists = sample_lists();
    doc = filled_document(
        _page(), lists, "Kijiji Cinema", _logo(), ["data:image/svg+xml;base64,AAAA"]
    );
    assert doc.startswith("<!doctype html>");
    assert doc.count("The Long Rains") >= 2 , "the hero and its card";
    assert "Nairobi Nights" in doc and "Matatu Run" in doc;
    assert "aspect-ratio:2/3" in doc and "z-index:1" in doc , "posters 2:3, above decorations";
    assert "mask:url(data:image/svg+xml;base64,AAAA)" in doc , "figures painted through their masks";
    assert "No showtimes today." not in doc , "an empty state hides when its list has items";
    assert "data:image/webp;base64," in doc , "the logo";
    assert "'Nunito'" in doc and "'Nunito Variable'" not in doc , "Google's family for the picture";
    bare = filled_document(
        _page(),
        {"featured": [], "films": [], "today": [], "soon": []},
        "Kijiji Cinema",
        _logo(),
        []
    );
    assert "No showtimes today." in bare and "Nothing showing yet." in bare;
    assert "display:none" in bare , "no figures: the motif slots hide";
}

test "the programme becomes the template's lists" {
    home = {
        "cinema": {"timezone": "Africa/Nairobi"},
        "movies": [
            {
                "movie_key": "m1",
                "title": "Rafiki",
                "age_rating": "16",
                "runtime_minutes": 83,
                "genres": ["Drama"],
                "synopsis": "Two young women."
            }
        ],
        "showtimes": [
            {
                "movie_key": "m1",
                "title": "Rafiki",
                "starts_at": "2099-01-02T16:15:00+00:00",
                "screen": {"name": "Screen 1"}
            }
        ],
        "page": {"sections": []}
    };
    lists = programme_lists(home, {"m1": "data:image/webp;base64,BBBB"});
    film = lists["featured"][0];
    assert film["film.title"] == "Rafiki"
        and film["film.details"] == "16 · 1 h 23 · Drama";
    assert film["_poster_url"] == "data:image/webp;base64,BBBB";
    assert film["times"][0]["show.time"] == "19:15" , "in the cinema's time zone";
    assert lists["today"] , "nothing today: the next showtimes stand in";
}

test "a review replaces the page; one that can't run or comes back incomplete keeps it" {
    page = _page();
    sent: list[int] = [];
    def shots(_document: str) -> list[bytes] {
        return [b"desktop", b"phone"];
    }
    def better(
        content: list[dict[str, any]],
        effort: str = "",
        max_tokens: int = 0,
        timeout: float = 0.0
    ) -> str {  # jac:ignore[W1037]
        sent.append(len(content));
        return _fixture().replace(
            "Tickets by AfriCinemas", "Tickets by AfriCinemas. Reviewed."
        );
    }
    pagereview.shoot = shots;
    pagereview.ask = better;
    reviewed = review_page(_logo(), "Kijiji Cinema", page, sample_lists(), []);
    assert reviewed["reviewed"] == "yes" and "Reviewed." in reviewed["html"];
    assert sent == [4] , "the logo, two screenshots and the brief";
    def broken(
        content: list[dict[str, any]],
        effort: str = "",
        max_tokens: int = 0,
        timeout: float = 0.0
    ) -> str {  # jac:ignore[W1037]
        return "<main data-part=\"home\"></main>";
    }
    pagereview.ask = broken;
    assert review_page(_logo(), "Kijiji Cinema", page, sample_lists(), []) == page;
    def declined(
        content: list[dict[str, any]],
        effort: str = "",
        max_tokens: int = 0,
        timeout: float = 0.0
    ) -> str {  # jac:ignore[W1037]
        raise ClaudeFailed("the model declined");
    }
    pagereview.ask = declined;
    assert review_page(_logo(), "Kijiji Cinema", page, sample_lists(), []) == page;
    def no_browser(_document: str) -> list[bytes] {
        raise ReviewSkipped("no browser");
    }
    pagereview.shoot = no_browser;
    assert review_page(_logo(), "Kijiji Cinema", page, sample_lists(), []) == page;
}
