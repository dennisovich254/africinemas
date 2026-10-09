# JI-043: A plain function with the same name as an endpoint in another module silently replaces the endpoint

- **Version:** jaclang 0.37.18, served apps (`jac run` / the in-process test client)
- **Found:** 2026-10-09, P8.1 (the AI agent's tools)
- **Status:** open. **High for this app** if hit (a public endpoint starts answering 401, or an endpoint is replaced by an unrelated function); worked around and guarded by a test.

## What happened
`core/agent/tools.jac` defined plain (non-endpoint) functions `hold_seats`, `place_order` and `my_tickets`, wrapping the endpoints of the same names in `core/booking/hold_api.jac`, `order_api.jac` and `customer_tickets.jac` (imported under aliases). Once an app imported both modules, a signed-out `POST /function/hold_seats` answered `401 UNAUTHORIZED`, while the other public endpoints of the same app answered normally:

```text
hold_seats                401 {"error": {"code": "UNAUTHORIZED"}}
my_order                  200
public_seat_availability  200
```

So the app's endpoint table is keyed by the bare function name, and the later plain function took the endpoint's place, with the default (login-required) access. Nothing warns: `jac check` is clean and the isolation registry still listed `hold_seats`. In the test payment app it broke every test that holds seats signed out (about 60 tests across all CI shards); the production app happened to keep the endpoint (import order).

## Expected
Endpoints are named by their module as well, or a second function under an endpoint's name is an error at compile or start time, not a silent swap.

## Workaround (in place)
- The agent's tools have names no endpoint uses: `hold_chosen_seats`, `prepare_order`, `my_bookings`.
- `tests/unit/agent_tools_tests.jac` fails if any tool's name is an endpoint name in the isolation registry.
- Rule for this app: never give a plain function the name of an endpoint anywhere in the app.
