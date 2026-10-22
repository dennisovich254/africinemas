"""An AI-designed storefront for the browser tests (ADR-0046 to ADR-0050), with no model.

The brand kit's plan (KIT_PLAN) and the written page (tests/fixtures/ai_storefront.html)
come from files the server reads (AFRICINEMAS_KIT_PLAN and AFRICINEMAS_PAGE_SCRIPT,
scripts/e2e_env.sh); CI has no model key, so the colours are built from the logo.

- logo_base64: a gold frame with a green bird inside it, as a PNG.
- script_design: writes the plan and the page where the server reads them.
- ai_designed(owner): the cinema's storefront designed from that logo with one call
  (design_storefront) and published, so every storefront page wears the written design.
"""

import io;
import os;
import json;
import base64;
import from PIL { Image, ImageDraw }
import from e2e.support.api { call }

glob KIT_PLAN: dict[str, any] = {  # jac:ignore[W1037]
         # The green bird inside the logo's frame; the logo is trimmed to the frame on
         # upload, so the box is in the trimmed logo's pixels.
         "motifs": [
             {
                 "name": "a dove in flight",
                 "box": [180, 8, 252, 76],
                 "colour": "#22553c"
             },
             {"name": "three doves", "box": [180, 8, 252, 76], "colour": "#22553c"}
         ],
         "card": "notched",
         "frame": "open",
         "divider": "motif",
         "heading": "caps",
         "fonts": "heritage",
         "header": "centred",
         "hero": "split",
         "surfaces": "flat",
         "density": "compact"
     };

def logo_base64 -> str {
    # A gold frame on white, with a green bird inside it.
    img = Image.new("RGB", (300, 120), (255, 255, 255));
    d = ImageDraw.Draw(img);
    d.rectangle((10, 10, 290, 110), outline=(201, 164, 58), width=6);
    d.ellipse((205, 45, 255, 80), fill=(34, 85, 60));
    d.polygon([(212, 52), (195, 22), (242, 48)], fill=(34, 85, 60));
    out = io.BytesIO();
    img.save(out, "PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def script_design {
    # The models' answers, as files the server reads: the plan and the written page.
    with open("tests/fixtures/ai_storefront.html") as src {
        with open(os.environ["AFRICINEMAS_PAGE_SCRIPT"], "w") as f {
            f.write(src.read());
        }
    }
    with open(os.environ["AFRICINEMAS_KIT_PLAN"], "w") as f {
        json.dump(KIT_PLAN, f);
    }
}

def ai_designed(owner: dict[str, str]) {
    # The storefront designed from the logo (the written page among it) and published.
    script_design();
    tenant = {"tenant": owner["slug"]};
    assert call(
        owner["token"],
        "upload_logo",
        {** tenant, "content_type": "image/png", "data_base64": logo_base64()}
    )["ok"];
    designed = call(owner["token"], "design_storefront", tenant);
    assert designed["ok"] , designed;
    assert call(owner["token"], "publish_theme", tenant)["ok"];
}
