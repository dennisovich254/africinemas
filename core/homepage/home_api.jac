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
- preview_home_page shows a draft as the storefront would, without saving it.
- Photos for the About section: upload_home_photo (checked and re-encoded like a
  poster), get_home_photo and remove_home_photo. A page may only show photos the cinema
  uploaded; public_home_photo serves those its published page shows.
- Everything needs tenant.settings.update. Another cinema's page answers not_found.
"""

import io;
import from uuid { uuid4 }
import from core.clock { now }
import from core.authz.context { TenantScope, scoped }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Movie }
import from core.catalog.venues { find_movie }
import from core.catalog.storefront { set_home, give_public_key }
import from core.catalog.storefront_api {
    programme,
    cinema_info,
    fill_page,
    photo_data_url
}
import from core.catalog.poster {
    PosterRejected,
    decode_upload,
    process_photo,
    media_key,
    media_store
}
import from core.homepage.models { HomePage, HomePageVersion }
import from core.homepage.page {
    TEMPLATES,
    SECTION_TYPES,
    LIMITS,
    default_page,
    parse_page,
    page_movie_ids,
    page_photos
}
import from core.audit.log { audited }

glob CONFIGURE: str = "tenant.settings.update",
     # How many photos a cinema may keep uploaded for its page at once.
     PHOTOS_KEPT: int = 12;

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

def _reference_problems(
    scope: TenantScope,
    page: dict[str, any],  # jac:ignore[W1037]
    home: HomePage | None
) -> list[dict[str, str]] {
    # A problem for every movie the page names that isn't this cinema's, and every
    # photo that isn't one it uploaded.
    problems: list[dict[str, str]] = [];
    uploaded: list[str] = list(home.photos) if home is not None else [];
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
        } elif s["type"] == "about" {
            for (j, photo) in enumerate(s["fields"]["photos"]) {
                if photo not in uploaded {
                    problems.append(
                        {
                            "path": f"sections.{i}.fields.photos.{j}",
                            "code": "unknown_photo",
                            "message": "Upload this photo again."
                        }
                    );
                }
            }
        }
    }
    return problems;
}

def _checked(scope: TenantScope, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # The page in its stored shape, or Refused("invalid_page") with every problem.
    (parsed, problems) = parse_page(page);
    found = [{"path": p.path, "code": p.code, "message": p.message} for p in problems];
    if parsed is not None {
        found = _reference_problems(scope, parsed, _home_page(scope));
    }
    if parsed is None or found {
        raise Refused(
            "invalid_page",
            "This page has problems to fix before it can be saved.",
            {"problems": found}
        );
    }
    return parsed;
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
    return _keyed(page, keys);
}

def _keyed(page: dict[str, any], keys: dict[str, str]) -> dict[str, any] {  # jac:ignore[W1037]
    # The page with movies named by key (`keys`: movie id -> key) instead of by id.
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
        "photos": list(home.photos) if home is not None else [],
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
    parsed = _checked(scope, page);
    _set_draft(scope, parsed);
    return {"ok": True, "page": parsed};
}

def _preview_home_page(tenant: str, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # The page as the storefront would show it, filled from today's programme, without
    # saving or publishing anything. Movies not yet on the storefront get stand-in keys
    # (so nothing is written), and photos come as data URLs.
    scope = scoped(tenant, CONFIGURE);
    parsed = _checked(scope, page);
    keys: dict[str, str] = {};
    known: dict[str, Movie] = {};
    for (i, movie_id) in enumerate(page_movie_ids(parsed)) {
        movie = find_movie(scope.tenant, movie_id);
        if movie is not None {
            key = movie.public_key or f"draft-{i}";
            keys[movie_id] = key;
            known[key] = movie;
        }
    }
    shaped = _keyed(parsed, keys);
    for s in shaped["sections"] {
        if s["type"] == "about" {
            s["fields"]["photos"] = [
                photo_data_url(scope.tenant, p) for p in s["fields"]["photos"]
            ];
        }
    }
    (entries, cards, _) = programme(scope.tenant);
    info = cinema_info(scope.tenant);
    return {
        "ok": True,
        "cinema": info,
        "page": fill_page(shaped, entries, cards, info["timezone"], known)
    };
}

def _upload_home_photo(
    tenant: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    home = _home_page(scope);
    if home is not None and len(home.photos) >= PHOTOS_KEPT {
        raise Refused(
            "too_many_photos",
            f"You can keep {PHOTOS_KEPT} photos. Remove one to add another."
        );
    }
    try {
        webp = process_photo(decode_upload(data_base64), content_type);
    } except PosterRejected as e {
        raise Refused(e.code, e.message);
    }
    name = uuid4().hex;
    key = media_key(scope.ctx.tenant_id, name);
    storage = media_store();
    storage.upload(io.BytesIO(webp), key);
    me = node_id(root);
    try {
        act_as(scope.tenant.principal_root_id);
        try {
            kept = _ensure(scope);
            kept.photos = list(kept.photos) + [name];
            kept.updated_at = now().isoformat();
            flush_now();
        } finally {
            restore(me);
        }
    } except Exception as e {
        storage.delete(key);
        raise e;
    }
    return {"ok": True, "photo": name};
}

def _get_home_photo(tenant: str, photo: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    home = _home_page(scope);
    if home is None or photo not in home.photos {
        raise Refused("unknown_photo", "That photo isn't uploaded.");
    }
    return {"ok": True, "photo": photo_data_url(scope.tenant, photo)};
}

def _remove_home_photo(tenant: str, photo: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Takes the photo out of the uploads and the draft. A published version that
    # shows it keeps it until it's no longer live; otherwise the file is deleted.
    scope = scoped(tenant, CONFIGURE);
    home = _home_page(scope);
    if home is None or photo not in home.photos {
        raise Refused("unknown_photo", "That photo isn't uploaded.");
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        kept = _ensure(scope);
        kept.photos = [
            p
            for p in kept.photos
            if p != photo
        ];
        draft = _draft(kept);
        for s in draft["sections"] {
            if s["type"] == "about" {
                s["fields"]["photos"] = [
                    p
                    for p in s["fields"]["photos"]
                    if p != photo
                ];
            }
        }
        kept.draft = draft;
        kept.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    in_use = any(photo in page_photos(v.page) for v in _versions(scope, home));
    if not in_use {
        key = media_key(scope.ctx.tenant_id, photo);
        on_commit(lambda { media_store().delete(key); });
    }
    return {"ok": True};
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

def _do_save_home_page(tenant: str, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _save_home_page(tenant, page); });  # jac:ignore[W1037]
}

def _do_publish_home_page(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _publish_home_page(tenant); });  # jac:ignore[W1037]
}

def _do_rollback_home_page(tenant: str, version: int) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _rollback_home_page(tenant, version); });  # jac:ignore[W1037]
}

def:priv preview_home_page(tenant: str, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _preview_home_page(tenant, page); });  # jac:ignore[W1037]
}

def _do_upload_home_photo(
    tenant: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _upload_home_photo(tenant, content_type, data_base64); }  # jac:ignore[W1037]
    );
}

def:priv get_home_photo(tenant: str, photo: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_home_photo(tenant, photo); });  # jac:ignore[W1037]
}

def _do_remove_home_photo(tenant: str, photo: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _remove_home_photo(tenant, photo); });  # jac:ignore[W1037]
}

def:priv save_home_page(tenant: str, page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "home_page.saved",
        "home_page",
        "",
        lambda -> any { return _do_save_home_page(tenant, page); }  # jac:ignore[W1037]
    );
}

def:priv publish_home_page(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "home_page.published",
        "home_page",
        "",
        lambda -> any { return _do_publish_home_page(tenant); }  # jac:ignore[W1037]
    );
}

def:priv rollback_home_page(tenant: str, version: int) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "home_page.rolled_back",
        "home_page",
        "",
        lambda -> any { return _do_rollback_home_page(tenant, version); },
        detail=f"to version {version}"  # jac:ignore[W1037]
    );
}

def:priv upload_home_photo(
    tenant: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "home_page.photo_uploaded",
        "photo",
        "",
        lambda -> any { return _do_upload_home_photo(
            tenant, content_type, data_base64
        ); },
        made="photo"  # jac:ignore[W1037]
    );
}

def:priv remove_home_photo(tenant: str, photo: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "home_page.photo_removed",
        "photo",
        photo,
        lambda -> any { return _do_remove_home_photo(tenant, photo); }  # jac:ignore[W1037]
    );
}
