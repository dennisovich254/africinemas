# ADR-0011: Movie posters: checked, re-encoded, stored under random keys, read through the API

- **Status:** Accepted
- **Date:** 2026-09-29
- **Sub-phase:** P3.4
- **Code:** `core/catalog/poster.jac`, `core/catalog/movie_api.jac`
- **Tests:** `tests/unit/poster_tests.jac`, `tests/integration/movie_tests.jac`

## Context
Architecture §56 asks uploads to be validated (MIME, file signature, size, dimensions, decoding limits), stored under a random key such as `tenant/{tenant_id}/media/{uuid}.webp`, and never at a path the client controls. Jac provides `store()` (local disk, or S3 via `[scale.storage]`). A Jac endpoint can't send image bytes or set its own status code (JI-033), and the browser's session token is in local storage, not a cookie, so a plain `<img src>` can't send it.

## Decision
1. **Check, then re-encode.**
   - Uploads arrive as base64 in the JSON body and are capped at 5 MB before decoding.
   - The declared type must be JPEG, PNG or WebP, and the file's signature bytes must match it.
   - Dimensions are read from the header and capped (8000 px a side, 40 megapixels) before the image is decoded, against decompression bombs.
   - Pillow (added to `[dependencies]`) decodes it; a file that fails to decode is refused. The result is re-encoded as WebP, at most 800 × 1200, from the pixels alone, so no metadata (GPS position, embedded payloads) survives.
2. **Random keys, never client paths.** Posters are stored at `tenant/{tenant_id}/media/{uuid4}.webp`. The client never supplies a filename or path.
3. **Read through the API.** `get_poster(tenant, movie_id)` returns the WebP as base64 behind `movies.read`, like every tenant endpoint. Another cinema's movie answers `not_found`. The browser shows it with a `data:` URL.
4. **Replay-safe writes.** The new file is written before the request commits and deleted if the request fails. The old file is deleted in `on_commit`.

## Consequences
- Posters aren't cached by the browser between visits. With S3 in production (plan 11.2), `store().get_url` can return presigned URLs instead, once the storefront needs them.
- A server crash between the graph commit and the end of the request can leave an unused file behind. The cleanup job in plan 11.1b can sweep media keys that no movie references.
- Local development stores files under `AFRICINEMAS_MEDIA_DIR` (default `./storage`, git-ignored).
