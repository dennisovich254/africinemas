"""A simulated M-Pesa (P5.1; ADR-0015): the PaymentProvider for tests and demos.

Each push's outcome is scripted by phone number (`outcomes`), else by the test numbers
below (like Safaricom's sandbox test numbers, for demos and browser tests), else
`default_outcome`:

- "success": paid; the callback and the query carry a receipt.
- "fail": insufficient funds (ResultCode 1).
- "cancel": the customer dismissed the prompt (1032).
- "timeout": no callback ever; the query says the phone couldn't be reached (1037).
- "late_success": no callback and the query says "still waiting", until pay_late();
  then both say paid.
- "reject": Daraja refuses the push itself.
- "unreachable" and "no_answer": Safaricom's side failing (P16.3): Daraja can't be
  reached, or doesn't answer the push.

Test numbers: 0700 000 001 fails, 0700 000 002 is cancelled, 0700 000 003 times out,
0700 000 004 is refused, 0700 000 005 can't reach M-Pesa, 0700 000 006 gets no answer and
0700 000 007 has its keys refused; any other number pays. `down` makes reachable() say
M-Pesa isn't answering, and `keys_refused` that it refuses our keys.

callback() is what Safaricom would POST to our callback URL (None while nothing has
been sent); query() is the status query. push_count() lets tests prove how many STK
prompts a reference caused, and paid_to() which paybill or till each one went to (P15.3:
each cinema's own; "" the platform's test one). State lives in the process: one per test or demo server.
"""

import from core.payments.state { PaymentState }
import from core.payments.provider {
    StkRequest,
    StkPushResult,
    StkStatus,
    PaymentProvider,
    valid_push,
    state_for_result
}

glob TEST_NUMBERS: dict[str, str] = {
         "254700000001": "fail",
         "254700000002": "cancel",
         "254700000003": "timeout",
         "254700000004": "reject",
         # Safaricom's side failing (P16.3): Daraja can't be reached, or doesn't answer.
         "254700000005": "unreachable",
         "254700000006": "no_answer",
         # A cinema's keys refused (P16.3): the cinema's problem, not Safaricom's.
         "254700000007": "credentials"
     },
     CODES: dict[str, int] = {"success": 0, "fail": 1, "cancel": 1032, "timeout": 1037},
     TEXTS: dict[str, str] = {
         "success": "The service request is processed successfully.",
         "fail": "The balance is insufficient for the transaction.",
         "cancel": "Request cancelled by user.",
         "timeout": "DS timeout user cannot be reached."
     };

obj SimulatedPush {
    has request: StkRequest,
        outcome: str,
        paid_late: bool = False;
}

obj SimulatedProvider(PaymentProvider) {
    has outcomes: dict[str, str] = {},
        default_outcome: str = "success",
        pushes: dict[str, SimulatedPush] = {},
        sent: dict[str, int] = {},
        sent_to: dict[str, str] = {},
        down: bool = False,
        keys_refused: bool = False;

    def reachable -> str {
        if self.down {
            return "unreachable";
        }
        return "refused" if self.keys_refused else "ok";
    }

    def stk_push(request: StkRequest) -> StkPushResult {
        problem = valid_push(request);
        if problem {
            return StkPushResult(
                accepted=False, error_code="invalid_request", message=problem
            );
        }
        outcome = self.outcomes.get(
            request.phone, TEST_NUMBERS.get(request.phone, self.default_outcome)
        );
        if outcome == "unreachable" {
            return StkPushResult(
                accepted=False,
                error_code="unavailable",
                message="M-Pesa can't be reached right now."
            );
        }
        if outcome == "credentials" {
            return StkPushResult(
                accepted=False,
                error_code="credentials",
                message="M-Pesa didn't accept this cinema's keys."
            );
        }
        if outcome == "no_answer" {
            return StkPushResult(
                accepted=False,
                error_code="timeout",
                message="M-Pesa didn't answer in time.",
                uncertain=True
            );
        }
        if outcome == "reject" {
            return StkPushResult(
                accepted=False,
                error_code="500.001.1001",
                message="Unable to lock subscriber, a transaction is already in process."
            );
        }
        self.sent[request.reference] = self.sent.get(request.reference, 0) + 1;
        self.sent_to[request.reference] = request.shortcode;
        checkout = f"ws_CO_SIM_{len(self.pushes) + 1:06d}";
        self.pushes[checkout] = SimulatedPush(request=request, outcome=outcome);
        return StkPushResult(
            accepted=True,
            checkout_request_id=checkout,
            message="Success. Request accepted for processing"
        );
    }

    def pay_late(checkout_request_id: str) {
        # A "late_success" customer pays after all.
        self.pushes[checkout_request_id].paid_late = True;
    }

    def push_count(reference: str) -> int {
        return self.sent.get(reference, 0);
    }

    def paid_to(reference: str) -> str {
        return self.sent_to.get(reference, "");
    }

    def _answer(checkout_request_id: str, outcome: str) -> StkStatus {
        push = self.pushes[checkout_request_id];
        code = CODES[outcome];
        paid = outcome == "success";
        return StkStatus(
            checkout_request_id=checkout_request_id,
            state=state_for_result(code),
            result_code=code,
            result_text=TEXTS[outcome],
            receipt=f"SIM{checkout_request_id[-6:]}X" if paid else "",
            amount_cents=push.request.amount_cents if paid else 0,
            phone=push.request.phone
        );
    }

    def _settled(checkout_request_id: str) -> str {
        # The outcome M-Pesa has by now ("" if the customer hasn't answered yet).
        push = self.pushes[checkout_request_id];
        if push.outcome == "late_success" {
            return "success" if push.paid_late else "";
        }
        return push.outcome;
    }

    def callback(checkout_request_id: str) -> StkStatus | None {
        if checkout_request_id not in self.pushes {
            return None;
        }
        outcome = self._settled(checkout_request_id);
        if outcome == "" or outcome == "timeout" {
            return None;
        }
        return self._answer(checkout_request_id, outcome);
    }

    def query(checkout_request_id: str) -> StkStatus {
        if checkout_request_id not in self.pushes {
            return StkStatus(
                checkout_request_id=checkout_request_id,
                state=PaymentState.UNKNOWN,
                result_text="The transaction is not found."
            );
        }
        outcome = self._settled(checkout_request_id);
        if outcome == "" {
            return StkStatus(
                checkout_request_id=checkout_request_id,
                state=PaymentState.STK_REQUESTED,
                result_text="The transaction is being processed."
            );
        }
        return self._answer(checkout_request_id, outcome);
    }
}
