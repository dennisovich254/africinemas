# JI-054: WebSockets can answer the sender or broadcast to everyone, but can't send to chosen users

- **Version:** jaclang 0.38.0
- **Found:** 2026-10-23, P13.5a (live updates for cinemas' help chats)
- **Kind:** feature request, not a bug
- **Status:** open, to report upstream after Phase 13 (owner, 2026-10-23); we check for new messages every few seconds instead

## What we wanted
In a support chat between a cinema and AfriCinemas, a new message should reach the other side at once. When AfriCinemas replies to Anga, only Anga's staff should get it, never another cinema's.

## What Jac offers
`@restspec(protocol=APIProtocol.WEBSOCKET)` on an `async walker` serves `ws://host/ws/<name>`. Messages can go two ways:

1. **To the sender:** each message the client sends runs the walker, and its `report`s come back on that connection.
2. **To everyone on the endpoint:** `broadcast=True` sends each response to every client connected to that walker (`WebSocketConnectionManager.broadcast_target(target_kind, target_name, payload)` in `jaclang/scale/websocket/websocket.jac`).

There's no third way: to a chosen set of connections, such as one user, the users of one tenant, or a named room. A broadcast reaches every connected client, whoever they are. For private messages, filtering in the browser is too late, because the data has already reached the device.

## What already works
- The connection is authenticated with the sign-in token before it's accepted (`ws_pre_accept_auth`), so the server knows who each connection belongs to.
- Across worker processes, broadcasts can be shared through Postgres: `[scale.websocket] backplane = "pg"`. The default, `memory`, keeps them in one process, and Jac warns about that when there's more than one worker.

## The request
A way to publish to a subset of connections, for example:

```jac
# Hypothetical API, for the shape of it:
await publish(channel=f"support:{tenant_id}", payload=message);
# Connections opt in to channels the server allows them, checked server-side:
subscribe(connection, f"support:{tenant_id}");
```

Or `broadcast_target` with a filter on the connection's user. It should go through the same backplane, so it works with several workers.

## Workaround (in place)
The chat page asks for new messages every few seconds while it's open, and pauses in a background tab. That's private (each request is the caller's own), works with any number of workers, and needs nothing new from Jac.
