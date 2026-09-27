"""P0.8b: theme -> CSS variables (scoped per surface, light + dark)."""

import re;
import from pathlib { Path }
import from core.theming.tokens { DEFAULT_THEME, ROLES, validate_theme }
import from core.theming.css {
    BACKOFFICE_THEME,
    SHADCN_MAP,
    SURFACES,
    theme_css,
    platform_stylesheet
}

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent;

def _block(css: str, selector: str) -> str {
    found = re.search(re.escape(selector) + r"\s*\{([^}]*)\}", css);
    assert found is not None , f"selector {selector!r} not found in:\n{css[:400]}";
    return found.group(1);
}

def _vars(block: str) -> dict[str, str] {
    return {k: v for (k, v) in re.findall(r"(--[a-z0-9-]+):\s*([^;]+);", block)};
}

test "light and dark blocks are scoped to the surface" {
    css = theme_css(DEFAULT_THEME, "storefront");
    light = _vars(_block(css, '[data-surface="storefront"]'));
    dark = _vars(_block(css, '.dark [data-surface="storefront"]'));
    assert light["--background"] == DEFAULT_THEME.light.background;
    assert dark["--background"] == DEFAULT_THEME.dark.background;
    assert light["--primary"] == DEFAULT_THEME.light.accent , "the tenant accent drives shadcn's primary";
    assert light["--primary-foreground"] == DEFAULT_THEME.light.on_accent;
}

test "every role and shadcn variable is emitted in both modes" {
    css = theme_css(DEFAULT_THEME, "storefront");
    for selector in [
        '[data-surface="storefront"]',
        '.dark [data-surface="storefront"]'
    ] {
        emitted = _vars(_block(css, selector));
        for role in ROLES {
            name = "--ac-" + role.replace("_", "-");
            assert name in emitted , f"{name} missing under {selector}";
        }
        for shadcn_var in SHADCN_MAP.keys() {
            assert shadcn_var in emitted , f"{shadcn_var} missing under {selector}";
        }
    }
}

test "fonts and radius come from the theme" {
    css = theme_css(DEFAULT_THEME, "storefront");
    light = _vars(_block(css, '[data-surface="storefront"]'));
    assert "Bebas Neue" in light["--font-display"];
    assert "Outfit" in light["--font-sans"];
    assert light["--radius"].endswith("rem");
}

test "only validated hex values reach the stylesheet" {
    css = theme_css(DEFAULT_THEME, "storefront")
        + theme_css(BACKOFFICE_THEME, "backoffice");
    for value in re.findall(
        r"--(?:ac-[a-z-]+|background|foreground|card|card-foreground|popover|popover-foreground|primary|primary-foreground|secondary|secondary-foreground|muted|muted-foreground|accent|accent-foreground|destructive|border|input|ring):\s*([^;]+);",
        css
    ) {
        assert re.fullmatch(r"#[0-9A-F]{6}", value) , f"non-hex colour value in CSS: {value!r}";
    }
}

test "unknown surfaces are rejected" {
    with testraises(ValueError) {
        theme_css(DEFAULT_THEME, "evil\"]{}body{display:none}");
    }
    assert set(SURFACES) == {"storefront", "backoffice"};
}

test "the back-office theme passes every contrast rule" {
    assert validate_theme(BACKOFFICE_THEME) == [] , f"{validate_theme(
        BACKOFFICE_THEME
    )}";
}

test "styles/brand.css is generated from the tokens (no hand edits)" {
    committed = (REPO_ROOT / "styles" / "brand.css").read_text();
    assert committed == platform_stylesheet() , "styles/brand.css is stale: run `jac run scripts/gen_brand_css.jac`";
}

test "keyboard focus is always drawn with the theme's focus-ring colour" {
    # P0.8c: one platform rule so every focusable element (ours and shadcn's) shows a
    # solid ring in the validated focus_ring colour (3:1 against background and surface).
    css = platform_stylesheet();
    rule = _block(css, "[data-surface] :focus-visible");
    assert "outline:" in rule and "var(--ring)" in rule , rule;
    assert "outline-offset:" in rule , rule;
    assert SHADCN_MAP["--ring"] == "focus_ring";
}

test "animations and transitions are switched off when the device asks for reduced motion" {
    # P0.8c (ui-ux-pro-max: "Reduced Motion", severity High).
    css = platform_stylesheet();
    start = css.find("@media (prefers-reduced-motion: reduce)");
    assert start >= 0 , "no reduced-motion rule";
    block = css[start:css.find("\n}\n", start)];
    assert "animation-duration: 0.01ms !important" in block , block;
    assert "transition-duration: 0.01ms !important" in block , block;
}
