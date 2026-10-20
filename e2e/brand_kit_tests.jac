"""The storefront wears the cinema's brand kit inside its own parts (ADR-0046).

The plan and the motif drawing come from files (AFRICINEMAS_KIT_PLAN, AFRICINEMAS_KIT_SCRIPT,
scripts/e2e_env.sh), never the real models. With a kit, the motif marks the section
headings, the divider and the footer, and the look shapes posters and headings; without
one, none of it shows.
"""

import io;
import os;
import json;
import base64;
import from PIL { Image, ImageDraw }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    context_options,
    artifact
}
import from e2e.support.api { call, owner_with_cinema, PASSWORD }
import from e2e.support.catalog { cinema_with_programme }

glob STOREFRONT: str = '[data-testid="storefront"]',
     PLAN: dict[str, any] = {  # jac:ignore[W1037]
         "motifs": ["a dove in flight", "three doves"],
         "card": "notched",
         "frame": "open",
         "divider": "motif",
         "heading": "caps",
         "fonts": "heritage",
         "header": "centred",
         "hero": "split",
         "surfaces": "flat",
         "density": "compact"
     },
     # A mark's paint, as the browser computes it.
     MASK_JS: str = """sel => { const e = document.querySelector(sel); if (!e) return ''; const s = getComputedStyle(e);
  return s.display + ' ' + (s.maskImage || s.webkitMaskImage || ''); }""";

def _bird_png -> bytes {
    # A black bird-like silhouette on white, as the image model draws one.
    img = Image.new("RGB", (400, 400), (255, 255, 255));
    d = ImageDraw.Draw(img);
    d.ellipse((140, 170, 300, 250), fill=(0, 0, 0));
    d.polygon([(170, 190), (90, 80), (230, 180)], fill=(0, 0, 0));
    d.polygon([(290, 200), (350, 180), (300, 230)], fill=(0, 0, 0));
    out = io.BytesIO();
    img.save(out, "PNG");
    return out.getvalue();
}

def _logo_base64 -> str {
    img = Image.new("RGB", (300, 120), (255, 255, 255));
    ImageDraw.Draw(img).rectangle((10, 10, 290, 110), outline=(201, 164, 58), width=6);
    out = io.BytesIO();
    img.save(out, "PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _scripts {
    # The models' answers, as files the server reads (scripts/e2e_env.sh), the written
    # storefront (ADR-0048) among them.
    with open("tests/fixtures/ai_storefront.html") as src {
        with open(os.environ["AFRICINEMAS_PAGE_SCRIPT"], "w") as f {
            f.write(src.read());
        }
    }
    with open(os.environ["AFRICINEMAS_KIT_SCRIPT"], "wb") as f {
        f.write(_bird_png());
    }
    with open(os.environ["AFRICINEMAS_KIT_PLAN"], "w") as f {
        json.dump(PLAN, f);
    }
}

def _kit(owner: dict[str, str]) {
    with open(os.environ["AFRICINEMAS_KIT_SCRIPT"], "wb") as f {
        f.write(_bird_png());
    }
    with open(os.environ["AFRICINEMAS_KIT_PLAN"], "w") as f {
        json.dump(PLAN, f);
    }
    tenant = {"tenant": owner["slug"]};
    assert call(
        owner["token"],
        "upload_logo",
        {** tenant, "content_type": "image/png", "data_base64": _logo_base64()}
    )["ok"];
    drawn = call(owner["token"], "draw_brand_kit", tenant);
    assert drawn["ok"] and len(drawn["kit"]["motifs"]) == 2 , drawn;
    assert call(owner["token"], "publish_theme", tenant)["ok"];
}

test "the storefront wears the cinema's brand kit inside its parts" {
    owner = cinema_with_programme();
    _kit(owner);
    (pw, browser) = shared_browser();
    try {
        for (project, scheme) in [
            ("desktop", "light"),
            ("desktop", "dark"),
            ("mobile", "light")
        ] {
            page = browser.new_context(
                **context_options(pw, project, scheme)
            ).new_page();
            page.goto(f"{BASE_URL}/c/{owner['slug']}");
            page.wait_for_selector('[data-testid="movie-card"]');
            shell = page.locator(STOREFRONT);
            assert shell.get_attribute("data-kit-motif") == "on";
            assert shell.get_attribute("data-kit-card") == "notched";
            heading = page.evaluate(
                MASK_JS, '[data-kit-slot="heading"] [data-kit-mark]'
            );
            # Shown (a flex item computes as block) and painted with the motif.
            assert not heading.startswith("none")
                and "data:image/webp" in heading , heading;
            assert "data:image/webp" in page.evaluate(MASK_JS, ".kit-sign") , "footer mark";
            divider = page.locator("[data-kit-divider-slot]").first;
            if divider.count() > 0 {
                assert divider.evaluate("e => getComputedStyle(e).display") == "flex";
            }
            caps = page.locator('[data-kit-slot="heading"]').first.evaluate(
                "e => getComputedStyle(e).textTransform"
            );
            assert caps == "uppercase";
            poster = page.locator(
                '[data-testid="movie-card"] [data-kit-slot="poster"]'
            ).first.evaluate(
                "e => getComputedStyle(e).maskImage || getComputedStyle(e).webkitMaskImage"
            );
            assert "radial-gradient" in poster , "notched posters";
            # The AI's design (ADR-0047): its fonts, hero, header and surfaces.
            assert shell.get_attribute("data-design-hero") == "split";
            title_font = page.locator('[data-testid="section-hero"] h2').evaluate(
                "e => getComputedStyle(e).fontFamily"
            );
            assert "Cinzel" in title_font , title_font;
            panel = page.locator('[data-testid="section-hero"]').evaluate(
                "e => getComputedStyle(e).gridTemplateColumns"
            );
            poster_box = page.locator(
                '[data-testid="section-hero"] [data-kit-slot="poster"]'
            ).bounding_box();
            if project == "mobile" {
                assert poster_box["height"] <= 260 , "the split poster is a band on phones";
            }
            if project == "desktop" {
                assert len(panel.split(" ")) == 2 , panel;
                logo = page.locator(
                    '[data-testid="storefront-name"] img'
                ).bounding_box();
                width = page.viewport_size["width"];
                assert abs((logo["x"] + logo["width"] / 2) - width / 2) < 40 , "logo centred";
            }
            page.screenshot(
                path=artifact(f"brandkit-{project}-{scheme}.png"), full_page=True
            );
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "without a brand kit none of it shows" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.goto(f"{BASE_URL}/c/{owner['slug']}");
        page.wait_for_selector(STOREFRONT);
        assert (page.locator(STOREFRONT).get_attribute("data-kit") or "") == "";
        assert page.locator(STOREFRONT).get_attribute("data-design-fonts") is None;
        assert page.evaluate(MASK_JS, ".kit-sign").startswith("none");
    } finally {
        close_contexts(browser);
    }
}

test "an owner designs their storefront from the logo with one button, then publishes it" {
    # The kit, its plan and the written page come from scripted files; CI has no model
    # key, so the colours are built from the logo's main colour.
    owner = cinema_with_programme();
    _scripts();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.goto(BASE_URL + "/login");
        page.fill("#email", owner["email"]);  # jac:ignore[W6002]
        page.fill("#password", PASSWORD);  # jac:ignore[W6002]
        page.click('button[type="submit"]');
        page.wait_for_url("**/app");
        page.goto(f"{BASE_URL}/app/{owner['slug']}/settings");
        page.wait_for_selector('[data-testid="branding"]');
        kit = '[data-testid="brand-kit"]';
        design = f'{kit} button:has-text("Design my storefront")';
        assert page.locator(design).count() == 0 , "needs a logo first";
        assert not page.locator('[data-testid="adjust-yourself"]').evaluate(
            "e => e.open"
        ) , "the owner's own editing is closed";
        logo = base64.b64decode(_logo_base64());
        page.set_input_files(
            "#logo-file",
            files=[{"name": "logo.png", "mimeType": "image/png", "buffer": logo}]
        );
        page.wait_for_selector('[data-testid="logo-preview"]');
        page.click(design);
        page.wait_for_selector('[data-testid="kit-motifs"] li', timeout=90000);
        assert page.locator('[data-testid="kit-motifs"] li').count() == 2;
        assert "AI wrote your storefront"
            in page.inner_text('[data-testid="kit-note"]');
        assert page.locator('[data-testid="kit-look"]').count() == 0 , "no look pickers";
        # The preview: the written page, filled with the cinema's real programme.
        preview = page.locator('[data-testid="ai-preview"]');
        preview.locator(
            '[data-testid="ai-home"] h3:has-text("Rafiki")'
        ).first.wait_for();
        page.screenshot(path=artifact("ai-branding-page.png"), full_page=True);
        assert "default"
            in page.inner_text('[data-testid="branding-status"]').lower() , "nothing public yet";
        page.click('button:has-text("Publish")');
        page.wait_for_selector('[data-testid="branding-status"]:has-text("Version 1")');
        page.goto(f"{BASE_URL}/c/{owner['slug']}");
        page.wait_for_selector('[data-testid="ai-home"]');
        assert page.locator('[data-testid="storefront-header"]').count() == 0 , "the AI's header replaces ours";
        assert page.locator('[data-testid="ai-header"] img[alt]').count() == 1 , "the logo";
        films = page.locator('[data-testid="ai-home"] article');
        assert films.count() == 2 , "one card per film on sale";
        assert page.locator('[data-testid="ai-home"] script').count() == 0;
        assert "evil.example" not in page.content();
        width = page.evaluate(
            "document.documentElement.scrollWidth - document.documentElement.clientWidth"
        );
        assert width == 0 , "no sideways scroll";
        page.screenshot(path=artifact("ai-storefront.png"), full_page=True);
        # A showtime link books that showtime through our own pages, under the AI's header.
        page.locator('[data-testid="ai-home"] #showtimes a').first.click();
        page.wait_for_url("**/s/**");
        page.wait_for_selector('[data-testid="ai-header"]');
        page.wait_for_selector('[data-testid="ai-footer"]');
        page.screenshot(path=artifact("ai-showtime-page.png"), full_page=True);
    } finally {
        close_contexts(browser);
    }
}
