# JI-054: WebSockets can answer the sender or broadcast to everyone, but can't send to chosen users

- **Version:** jaclang 0.38.0
- **Found:** 2026-10-23, P13.5a (live updates for cinemas' help chats)
- **Kind:** feature request, not a bug
- **Status:** open, to report upstream after Phase 13 (owner, 2026-10-23); we check for new messages every few seconds instead

## What we wanted
In a support chat between a cinema and AfriCinemas, a new message should reach the other side at once. When AfriCinemas replies to Anga, only Anga's staff should get it, never another cinema's.

## In one picture: a hotel
The **server** is the front desk; each **browser page** is a guest in a room.

- **Plain HTTP** is walking down to the desk to ask a question and walking back. The desk can never come up to a room, so a guest who wants news keeps walking down to ask ("anything for me?"). That's polling.
- **A WebSocket** is a phone line from the room to the desk that stays connected. Either side can speak at any time, so the desk can ring a room the moment something happens. That's what a chat needs: when AfriCinemas replies to Anga, the desk rings Anga's room, and only that one.

Jac's receptionist has **two moves**:
1. **Answer a call.** When a room phones in, the receptionist replies on that same call, and only because that room spoke.
2. **The loudspeaker** (`broadcast=True`). Whatever is said plays in every room with a line to that desk.

The move a chat needs is missing: **"ring room 12"**, speaking to one chosen room, or one group of rooms, on the desk's own initiative. The receptionist does know whose room is whose: key cards (sign-in tokens) are checked when a line is connected. But our code can't use that to pick a room.

So when our support agent replies to Anga:
- the message comes down **the agent's** line, so move 1 can only answer the agent;
- Anga's line is idle, since Anga didn't phone in;
- the only way to reach Anga is the loudspeaker (move 2), which plays Anga's private message in every room, other cinemas' included.

## What Jac offers
`@restspec(protocol=APIProtocol.WEBSOCKET)` on an `async walker` serves `ws://host/ws/<name>`. Messages can go two ways:

1. **To the sender:** each message the client sends runs the walker, and its `report`s come back on that connection.
2. **To everyone on the endpoint:** `broadcast=True` sends each response to every client connected to that walker (`WebSocketConnectionManager.broadcast_target(target_kind, target_name, payload)` in `jaclang/scale/websocket/websocket.jac`).

There's no third way: to a chosen set of connections, such as one user, the users of one tenant, or a named room. A broadcast reaches every connected client, whoever they are. For private messages, filtering in the browser is too late, because the data has already reached the device.

## What already works
- The connection is authenticated with the sign-in token before it's accepted (`ws_pre_accept_auth`), so the server knows who each connection belongs to.
- Across worker processes, broadcasts can be shared through Postgres: `[scale.websocket] backplane = "pg"`. The default, `memory`, keeps them in one process, and Jac warns about that when there's more than one worker.

## How other toolkits do it: Django Channels
Django Channels calls the missing move **groups**. A connection joins the groups the server allows it, and a message to a group reaches only the connections in it, across every worker process, through its channel layer (Redis or Postgres):

```python
# consumers.py
from channels.generic.websocket import AsyncJsonWebsocketConsumer

class SupportConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope["user"]  # checked at connect, like Jac's key cards
        if not user.is_authenticated:
            await self.close()
            return
        self.group = f"support.{user.cinema_id}"  # one cinema's staff only
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group, self.channel_name)

    async def support_message(self, event):  # called for "support.message" events
        await self.send_json(event["message"])
```

```python
# Anywhere on the server, such as when AfriCinemas replies to a cinema:
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

async_to_sync(get_channel_layer().group_send)(
    f"support.{cinema_id}",  # rings only that cinema's rooms
    {"type": "support.message", "message": {"text": text, "at": at}},
)
```

That is "ring the rooms of group X": `group_add` when a line is connected, `group_discard` when it hangs up, and `group_send` from anywhere on the server.

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
