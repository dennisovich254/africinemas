Daraja response bodies for the adapter's contract tests (plan 5.2, `tests/unit/daraja_tests.jac`).

They follow the formats in Safaricom's Daraja documentation (OAuth, STK push, STK query,
STK callback). Identifiers and receipts are made up. Plan 5.7 runs a real sandbox payment;
when it does, replace these with recorded sandbox responses (secrets, tokens and phone
numbers removed) and keep the tests passing.
