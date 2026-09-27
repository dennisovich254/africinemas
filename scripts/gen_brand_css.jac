"""Regenerate styles/brand.css from the theme tokens: jac run scripts/gen_brand_css.jac"""

import from pathlib { Path }
import from core.theming.css { platform_stylesheet }

with entry {
    target = Path(__file__).resolve().parent.parent / "styles" / "brand.css";
    target.write_text(platform_stylesheet());
    print(f"wrote {target}");
}
