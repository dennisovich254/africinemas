"""Guard (JI-047): no server route with a path parameter shares a prefix with a page.

In `jac run --dev`, Vite proxies a parameterised `@restspec` path by its static prefix
(`/c/{slug}/mcp` proxied all of `/c`), so every client page under that prefix answered
the API's JSON 404 in dev while CI and production, which don't run Vite, served it.
"""

import re;
import from pathlib { Path }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     RESTSPEC_PATH: str = r'@restspec\([^)]*?path\s*=\s*"([^"]+)"',
     CLIENT_ROUTE: str = r'<Route\s+path="([^"]+)"';

def proxied_prefixes(sources: list[str]) -> list[str] {
    # The prefix Vite's dev proxy takes for each parameterised server route.
    found: list[str] = [];
    for source in sources {
        for path in re.findall(RESTSPEC_PATH, source, re.S) {
            if "{" in path {
                found.append(path.split("{")[0].rstrip("/"));
            }
        }
    }
    return found;
}

def collisions(prefixes: list[str], routes: list[str]) -> list[str] {
    # Page routes the dev proxy would send to the API.
    hits: list[str] = [];
    for prefix in prefixes {
        for route in routes {
            if route == prefix or route.startswith(prefix + "/") {
                hits.append(f"{route} (proxied by {prefix})");
            }
        }
    }
    return hits;
}

test "no parameterised server route swallows a page route in dev" {
    sources = [
        p.read_text()
        for p in sorted((REPO_ROOT / "core").rglob("*.jac"))
        if ".jac" not in p.parts
    ]
        + [(REPO_ROOT / "main.jac").read_text()];
    routes = re.findall(CLIENT_ROUTE, (REPO_ROOT / "web" / "AppRoot.jac").read_text());
    assert len(routes) > 10 , f"found only {len(routes)} page routes";
    hits = collisions(proxied_prefixes(sources), routes);
    assert hits == [] , "these pages would hit the API in `jac run --dev`:\n"
        + "\n".join(hits);
}

test "the guard catches the collision it exists for" {
    old = proxied_prefixes(['@restspec(method=HTTPMethod.POST, path="/c/{slug}/mcp")']);
    assert old == ["/c"];
    assert collisions(old, ["/c/:slug", "/login"]) == ["/c/:slug (proxied by /c)"];
    assert collisions(["/mcp/c"], ["/c/:slug", "/mcp"]) == [];
}
