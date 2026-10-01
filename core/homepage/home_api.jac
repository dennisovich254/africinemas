"""A cinema's home page (P4.1b, architecture §41, §55). Tenant-scoped endpoints, listed in
tests/isolation/registry.jac; the storefront reads the published page through
public_home (core/catalog/storefront_api.jac).

- The owner edits a draft: save_home_page checks it with page.parse_page and checks that
  every movie it names is this cinema's. A refused page answers "invalid_page" with
  every problem, each with its field's path.
- publish_home_page makes the draft the next numbered HomePageVersion and puts it on
  the storefront, with movies named by their public keys; publishing what is already
  public is refused. rollback_home_page publishes an earlier version again, as the next
  version, and makes it the draft.
- Everything needs tenant.settings.update. Another cinema's page answers not_found.
"""

import from core.clock { now }
import from core.authz.context { TenantScope, scoped }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Movie }
import from core.catalog.venues { find_movie }
import from core.catalog.storefront { set_home, give_public_key }
import from core.homepage.models { HomePage, HomePageVersion }
import from core.homepage.page {
    TEMPLATES,
    SECTION_TYPES,
    LIMITS,
    default_page,
    parse_page,
    page_movie_ids
}

glob CONFIGURE: str = "tenant.settings.update";

def _home_page(scope: TenantScope) -> HomePage | None {
    if not scope.tenant.home_page_id {
        return None;
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found: any = jobj(scope.tenant.home_page_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as HomePage if isinstance(found, HomePage) else None;
}

def _ensure(scope: TenantScope) -> HomePage {
    # The cinema's HomePage, made on first use. Call as the cinema's principal.
    found = _home_page(scope);
    if found is not None {
        return found as HomePage;
    }
    made = HomePage(tenant_id=scope.ctx.tenant_id);
    scope.tenant ++> made;
    attach_to_tenant(made, scope.tenant);
    # Two first saves both write this, so the database lets only one through.
    scope.tenant.home_page_id = node_id(made);
    return made;
}

def _versions(scope: TenantScope, home: HomePage | None) -> list[HomePageVersion] {
    # Published versions, newest first.
    if home is None {
        return [];
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found = [home-->[?:HomePageVersion]];
    } finally {
        restore(me);
    }
    return sorted(
        found,
        key=lambda (v: HomePageVersion) -> int { return v.version; },
        reverse=True
    );
}

def _draft(home: HomePage | None) -> dict[str, any] {  # jac:ignore[W1037]
    if home is None or not home.draft {
        return default_page();
    }
    return dict(home.draft);
}

def _movies(scope: TenantScope) -> list[Movie] {
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found = [scope.tenant-->[?:Movie]];
    } finally {
        restore(me);
    }
    return sorted(found, key=lambda (m: Movie) -> str { return m.title.casefold(); });
}

def _movie_problems(scope: TenantScope, page: dict[str, any]) -> list[dict[str, str]] {  # jac:ignore[W1037]
    # A problem for every movie the page names that isn't this cinema's.
    problems: list[dict[str, str]] = [];
    def check(path: str, movie_id: str) {
        if movie_id and find_movie(scope.tenant, movie_id) is None {
            problems.append(
                {
                    "path": path,
                    "code": "unknown_movie",
                    "message": "Choose one of this cinema's movies."
                }
            );
        }
    }
    for (i, s) in enumerate(page["sections"]) {
        if s["type"] == "hero" {
            check(f"sections.{i}.fields.movie_id", s["fields"]["movie_id"]);
        } elif s["type"] == "coming_soon" {
            for (j, movie_id) in enumerate(s["fields"]["movie_ids"]) {
                check(f"sections.{i}.fields.movie_ids.{j}", movie_id);
            }
        }
    }
    return problems;
}

def _public_page(scope: TenantScope, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # The page as the storefront keeps it: movies named by public key (given here,
    # as the cinema's principal), never by id.
    keys: dict[str, str] = {};
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        for movie_id in page_movie_ids(page) {
            movie = find_movie(scope.tenant, movie_id);
            if movie is not None {
                give_public_key(movie);
                keys[movie_id] = movie.public_key;
            }
        }
        flush_now();
    } finally {
        restore(me);
    }
    sections: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in page["sections"] {
        fields = dict(s["fields"]);
        if s["type"] == "hero" {
            fields["movie_key"] = keys.get(fields.pop("movie_id"), "");
        } elif s["type"] == "coming_soon" {
            fields["movie_keys"] = [
                keys[m]
                for m in fields.pop("movie_ids")
                if m in keys
            ];
        }
        sections.append({"type": s["type"], "visible": s["visible"], "fields": fields});
    }
    return {"template": page["template"], "sections": sections};
}

def _view(scope: TenantScope, home: HomePage | None) -> dict[str, any] {  # jac:ignore[W1037]
    versions = _versions(scope, home);
    latest = versions[0] if versions else None;
    return {
        "draft": _draft(home),
        "published": {
            "version": latest.version,
            "page": latest.page,
            "published_at": latest.published_at
        }
            if latest is not None
            else None,
        "versions": [
            {
                "version": v.version,
                "template": v.page.get("template", ""),
                "published_at": v.published_at
            } for v in versions
        ]
    };
}

def _get_home_page(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    return {
        "ok": True,
        "home": _view(scope, _home_page(scope)),
        # What the editor may offer, so it never keeps its own copy.
        "options": {
            "templates": TEMPLATES,
            "section_types": SECTION_TYPES,
            "limits": LIMITS,
            "movies": [
                {"movie_id": node_id(m), "title": m.title} for m in _movies(scope)
            ]
        }
    };
}

def _set_draft(scope: TenantScope, page: dict[str, any]) {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        home = _ensure(scope);
        home.draft = page;
        home.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
}

def _save_home_page(tenant: str, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    (parsed, problems) = parse_page(page);
    found = [{"path": p.path, "code": p.code, "message": p.message} for p in problems];
    if parsed is not None {
        found = _movie_problems(scope, parsed);
    }
    if parsed is None or found {
        raise Refused(
            "invalid_page",
            "This page has problems to fix before it can be saved.",
            {"problems": found}
        );
    }
    _set_draft(scope, parsed);
    return {"ok": True, "page": parsed};
}

def _publish(scope: TenantScope, page: dict[str, any]) -> int {  # jac:ignore[W1037]
    # Publishes `page` as the next version; returns its number.
    stamp = now().isoformat();
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        home = _ensure(scope);
        home.version += 1;  # makes concurrent publishes clash (see models)
        published = HomePageVersion(
            tenant_id=scope.ctx.tenant_id,
            version=home.version,
            page=page,
            published_at=stamp
        );
        home ++> published;
        attach_to_tenant(published, scope.tenant);
        flush_now();
    } finally {
        restore(me);
    }
    set_home(scope.tenant, _public_page(scope, page));
    return published.version;
}

def _publish_home_page(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    home = _home_page(scope);
    page = _draft(home);
    versions = _versions(scope, home);
    public = versions[0].page if versions else default_page();
    if page == public {
        raise Refused(
            "nothing_to_publish", "The storefront already shows this home page."
        );
    }
    return {"ok": True, "version": _publish(scope, page)};
}

def _rollback_home_page(tenant: str, version: int) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    chosen = [
        v
        for v in _versions(scope, _home_page(scope))
        if v.version == version
    ];
    if not chosen {
        raise Refused("unknown_version", f"There is no published version {version}.");
    }
    page = dict(chosen[0].page);
    _set_draft(scope, page);
    return {"ok": True, "version": _publish(scope, page)};
}

def:priv get_home_page(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_home_page(tenant); });  # jac:ignore[W1037]
}

def:priv save_home_page(tenant: str, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _save_home_page(tenant, page); });  # jac:ignore[W1037]
}

def:priv publish_home_page(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _publish_home_page(tenant); });  # jac:ignore[W1037]
}

def:priv rollback_home_page(tenant: str, version: int) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _rollback_home_page(tenant, version); });  # jac:ignore[W1037]
}
