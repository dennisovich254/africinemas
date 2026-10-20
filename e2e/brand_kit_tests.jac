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
    # The models' answers, as files the server reads (scripts/e2e_env.sh).
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

test "an owner draws their brand, changes its look and publishes it" {
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
        assert page.locator(f'{kit} button:has-text("Draw my brand")').count() == 0 , "needs a logo first";
        logo = base64.b64decode(_logo_base64());
        page.set_input_files(
            "#logo-file",
            files=[{"name": "logo.png", "mimeType": "image/png", "buffer": logo}]
        );
        page.wait_for_selector('[data-testid="logo-preview"]');
        page.click(f'{kit} button:has-text("Draw my brand")');
        page.wait_for_selector('[data-testid="kit-motifs"] li', timeout=60000);
        assert page.locator('[data-testid="kit-motifs"] li').count() == 2;
        look = '[data-testid="kit-look"]';
        assert page.locator(f'{look} input[value="notched"]').is_checked() , "the plan's look";
        page.locator(f'{look} label:has-text("Rounded") input').check();
        page.wait_for_selector('[data-testid="kit-note"]:has-text("Saved")');
        page.click('button:has-text("Publish")');
        page.wait_for_selector('[data-testid="branding-status"]:has-text("Version 1")');
        page.goto(f"{BASE_URL}/c/{owner['slug']}");
        page.wait_for_selector('[data-testid="movie-card"]');
        assert page.locator(STOREFRONT).get_attribute("data-kit-card") == "rounded";
        page.goto(f"{BASE_URL}/app/{owner['slug']}/settings");
        page.wait_for_selector('[data-testid="kit-motifs"] li');
        page.screenshot(path=artifact("brandkit-branding-page.png"), full_page=True);
    } finally {
        close_contexts(browser);
    }
}
