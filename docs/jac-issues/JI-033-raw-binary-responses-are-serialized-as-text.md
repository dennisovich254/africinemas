# JI-033: A `@restspec(envelope=False)` endpoint can't return binary data or its own status

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-29, P3.4 (serving movie posters)
- **Status:** open (posters are returned as base64 inside the JSON response instead)

## What we saw (real server, `jac run`, checked with `curl`)
```jac
@restspec(method=HTTPMethod.GET, path="/media/poster", produces="image/png", envelope=False)
def:pub poster(key: str, sig: str) -> bytes {
    return PNG;   # a valid 67-byte PNG
}
```
```
HTTP/1.1 200 OK
Content-Type: image/png
Content-Length: 211
body: b"\x89PNG\r\n\x1a\n...      <- the Python repr of the bytes, not the bytes
```
The content type is honoured, but the body is `str(bytes)`, so a browser can't display it.

Returning `jaclang.server.serving.datatypes.Response(content=..., status_code=403, media_type=...)` instead doesn't help: the object is serialized to JSON (`{"__type__": "Response", ... "status_code": 403 ...}`) and sent with status 200. Raising an exception gives a 500. So such an endpoint can neither send binary content nor choose its status code.

The release notes (`@restspec` ... "honoring `produces` / `envelope` by returning the raw payload with that media type") suggest raw payloads are meant to work; text payloads may, but we only tested bytes.

## Workaround (in place)
`get_poster` is an ordinary JSON endpoint that returns the poster as base64 WebP; the browser shows it with a `data:` URL. Posters are re-saved at no more than 800 x 1200 px to keep that small. With S3 storage in production, `store().get_url` can hand out presigned URLs instead.

## Also hit by (2026-10-09, P8.2)
The MCP endpoint (`POST /mcp`) should answer a JSON-RPC notification with 202 Accepted and no body. It can't choose its status, so it sends 200 with `{}`; MCP clients ignore the body of a reply to a notification (ADR-0031).
