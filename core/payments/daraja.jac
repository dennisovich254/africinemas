"""The Daraja adapter (P5.2, architecture §29-§34; ADR-0016): M-Pesa through Safaricom.

A PaymentProvider over Daraja's REST API:

- OAuth: a client-credentials token (Basic key:secret), reused until shortly before it
  expires (expires_in, less TOKEN_MARGIN_S) and fetched again when Safaricom refuses it
  early (HTTP 401, or errorCode 404.001.03: one new token, one repeat of the call).
- STK push (/mpesa/stkpush/v1/processrequest): the shortcode, a password of
  base64(shortcode + passkey + timestamp) with the timestamp in Nairobi time, whole
  shillings, the customer's 2547/2541 number and an https callback URL. A push is
  never retried: Daraja has no idempotency key, so a retry could prompt the customer
  twice. A push that gets no answer is reported as uncertain.
- STK query (/mpesa/stkpushquery/v1/query): ResultCode to state; "being processed" is
  still waiting (STK_REQUESTED); an unknown CheckoutRequestID, or no answer after
  `retries` repeats, is UNKNOWN. Reads are safe to repeat, so they are retried.
- parse_callback: Safaricom's callback body as an StkStatus, with the receipt, amount and
  phone on success. The body is never proof of payment (§33); plan 5.4 confirms it with
  a query.

Secrets never reach the logs: the config prints without them, tokens and passwords are
never logged, and phone numbers are masked. The transport (`http`) and the clock are
injected; UrllibHttp is the real transport.
"""

import json;
import time;
import base64;
import socket;
import logging;
import urllib.error;
import urllib.request;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.payments.state { PaymentState }
import from core.payments.provider {
    StkRequest,
    StkPushResult,
    StkStatus,
    PaymentProvider,
    valid_push,
    state_for_result
}

glob SANDBOX_URL: str = "https://sandbox.safaricom.co.ke",
     NAIROBI: ZoneInfo = ZoneInfo("Africa/Nairobi"),
     TOKEN_MARGIN_S: int = 60,
     PROCESSING: str = "500.001.1001",
     INVALID_TOKEN: str = "404.001.03",
     LOG: logging.Logger = logging.getLogger("africinemas.payments.daraja");

class DarajaUnavailable(ConnectionError) {}

obj DarajaConfig {
    # One merchant's Daraja credentials. transaction_type is CustomerPayBillOnline for
    # a Paybill and CustomerBuyGoodsOnline for a Till.
    has consumer_key: str,
        consumer_secret: str,
        shortcode: str,
        passkey: str,
        base_url: str = SANDBOX_URL,
        transaction_type: str = "CustomerPayBillOnline";

    def __repr__ -> str {
        # Never the key, secret or passkey (they would reach any log that prints it).
        return f"DarajaConfig(base_url={self.base_url!r}, shortcode={self.shortcode!r}, transaction_type={self.transaction_type!r})";
    }

    def __str__ -> str {
        return self.__repr__();
    }
}

obj UrllibHttp {
    # The real transport: JSON over HTTPS. Returns (status, body); raises TimeoutError
    # or DarajaUnavailable when Daraja can't be reached.
    def send(
        method: str,
        url: str,
        headers: dict[str, str],
        body: dict[str, any] | None,  # jac:ignore[W1037]
        timeout: float
    ) -> tuple[int, dict[str, any]] {  # jac:ignore[W1037]
        data = json.dumps(body).encode() if body is not None else None;
        sent = urllib.request.Request(url, data=data, headers=headers, method=method);
        if data is not None {
            sent.add_header("Content-Type", "application/json");
        }
        try {
            with urllib.request.urlopen(sent, timeout=timeout) as reply {
                return (reply.status, _json(reply.read()));
            }
        } except urllib.error.HTTPError as e {
            return (e.code, _json(e.read()));
        } except (socket.timeout, TimeoutError) {
            raise TimeoutError("Daraja did not answer in time");
        } except urllib.error.URLError as e {
            if isinstance(e.reason, (socket.timeout, TimeoutError)) {
                raise TimeoutError("Daraja did not answer in time");
            }
            raise DarajaUnavailable("Daraja could not be reached");
        }
    }
}

def _json(raw: bytes) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        found = json.loads(raw.decode("utf-8") or "{}");
    } except ValueError {
        return {};
    }
    return found if isinstance(found, dict) else {};
}

def daraja_timestamp(at: datetime) -> str {
    # YYYYMMDDHHMMSS in Nairobi time, as Daraja expects.
    return at.astimezone(NAIROBI).strftime("%Y%m%d%H%M%S");
}

def stk_password(shortcode: str, passkey: str, timestamp: str) -> str {
    return base64.b64encode(f"{shortcode}{passkey}{timestamp}".encode()).decode();
}

def masked(phone: str) -> str {
    # 254712345678 -> 2547*****678, for logs.
    return phone[:4] + "*****" + phone[-3:] if len(phone) > 7 else "***";
}

def _metadata(callback: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    found: dict[str, any] = {};  # jac:ignore[W1037]
    meta = callback.get("CallbackMetadata") or {};
    for item in meta.get("Item") or [] {
        if isinstance(item, dict) and "Name" in item {
            found[str(item["Name"])] = item.get("Value");
        }
    }
    return found;
}

def parse_callback(body: any) -> StkStatus | None {  # jac:ignore[W1037]
    # Safaricom's STK callback as a status; None when it isn't one.
    if not isinstance(body, dict) {
        return None;
    }
    callback = (body.get("Body") or {}).get("stkCallback");
    if not isinstance(callback, dict) {
        return None;
    }
    checkout = callback.get("CheckoutRequestID");
    code = callback.get("ResultCode");
    if not isinstance(checkout, str) or not checkout {
        return None;
    }
    try {
        result = int(code);
    } except (TypeError, ValueError) {
        return None;
    }
    state = state_for_result(result);
    meta = _metadata(callback);
    paid = state == PaymentState.SUCCESS;
    amount = meta.get("Amount");
    return StkStatus(
        checkout_request_id=checkout,
        state=state,
        result_code=result,
        result_text=str(callback.get("ResultDesc", "")),
        receipt=str(meta.get("MpesaReceiptNumber", "")) if paid else "",
        amount_cents=round(float(amount) * 100)
            if paid and isinstance(amount, (int, float))
            else 0,
        phone=str(meta.get("PhoneNumber", "")) if paid else ""
    );
}

obj DarajaProvider(PaymentProvider) {
    has config: DarajaConfig,
        http: any = None,  # jac:ignore[W1037]
        clock: any = None,  # jac:ignore[W1037]
        timeout_s: float = 15.0,
        retries: int = 2,
        backoff_s: float = 1.0,
        token: str = "",
        token_until: datetime | None = None;

    def _now -> datetime {
        return self.clock.now() if self.clock is not None else now();
    }

    def _transport -> any {  # jac:ignore[W1037]
        if self.http is None {
            self.http = UrllibHttp();
        }
        return self.http;
    }

    def _login {
        # A new token; raises TimeoutError or DarajaUnavailable if Daraja can't give one.
        basic = base64.b64encode(
            f"{self.config.consumer_key}:{self.config.consumer_secret}".encode()
        ).decode();
        for attempt in range(self.retries + 1) {
            try {
                (status, body) = self._transport().send(
                    "GET",
                    f"{self.config.base_url}/oauth/v1/generate?grant_type=client_credentials",
                    {"Authorization": f"Basic {basic}"},
                    None,
                    self.timeout_s
                );
            } except (TimeoutError, OSError) as e {
                LOG.warning(
                    "Daraja login failed (attempt %d): %s",
                    attempt + 1,
                    type(e).__name__
                );
                time.sleep(self.backoff_s * (attempt + 1));
                continue;
            }
            if status == 200 and body.get("access_token") {
                self.token = str(body["access_token"]);
                lifetime = int(body.get("expires_in", 3599) or 3599);
                self.token_until = self._now()
                    + timedelta(seconds=lifetime - TOKEN_MARGIN_S);
                LOG.info("Daraja login ok (token valid %d s)", lifetime);
                return;
            }
            LOG.warning(
                "Daraja login refused: HTTP %d %s", status, body.get("errorCode", "")
            );
            raise DarajaUnavailable("Daraja refused the credentials");
        }
        raise DarajaUnavailable("Daraja login failed");
    }

    def _bearer -> str {
        if not self.token
            or self.token_until is None
            or self._now() >= self.token_until {
            self._login();
        }
        return self.token;
    }

    def _post(path: str, body: dict[str, any]) -> tuple[int, dict[str, any]] {  # jac:ignore[W1037]
        # One authorised POST; a refused token is replaced once and the call repeated.
        url = f"{self.config.base_url}{path}";
        (status, reply) = self._transport().send(
            "POST",
            url,
            {"Authorization": f"Bearer {self._bearer()}"},
            body,
            self.timeout_s
        );
        if status == 401 or reply.get("errorCode") == INVALID_TOKEN {
            # Daraja reports a refused token as HTTP 401 or as errorCode 404.001.03
            # (with HTTP 404); either way nothing was done, so a new token and one
            # repeat are safe, for a push too.
            LOG.info("Daraja refused the token (HTTP %d); logging in again", status);
            self.token = "";
            (status, reply) = self._transport().send(
                "POST",
                url,
                {"Authorization": f"Bearer {self._bearer()}"},
                body,
                self.timeout_s
            );
        }
        return (status, reply);
    }

    def _signed -> dict[str, any] {  # jac:ignore[W1037]
        stamp = daraja_timestamp(self._now());
        return {
            "BusinessShortCode": self.config.shortcode,
            "Password": stk_password(self.config.shortcode, self.config.passkey, stamp),
            "Timestamp": stamp
        };
    }

    def stk_push(request: StkRequest) -> StkPushResult {
        problem = valid_push(request);
        if not problem and not request.callback_url.startswith("https://") {
            problem = "Daraja needs an https callback URL.";
        }
        if problem {
            return StkPushResult(
                accepted=False, error_code="invalid_request", message=problem
            );
        }
        body = self._signed();
        body["TransactionType"] = self.config.transaction_type;
        body["Amount"] = request.amount_cents // 100;
        body["PartyA"] = request.phone;
        body["PartyB"] = self.config.shortcode;
        body["PhoneNumber"] = request.phone;
        body["CallBackURL"] = request.callback_url;
        body["AccountReference"] = request.account[:12];
        body["TransactionDesc"] = request.description[:13];
        try {
            (status, reply) = self._post("/mpesa/stkpush/v1/processrequest", body);
        } except TimeoutError {
            LOG.warning(
                "STK push for %s got no answer; outcome uncertain", request.reference
            );
            return StkPushResult(
                accepted=False,
                error_code="timeout",
                message="M-Pesa didn't answer in time.",
                uncertain=True
            );
        } except OSError {
            LOG.warning("STK push for %s: Daraja unreachable", request.reference);
            return StkPushResult(
                accepted=False,
                error_code="unavailable",
                message="M-Pesa can't be reached right now."
            );
        }
        checkout = reply.get("CheckoutRequestID");
        if status == 200 and str(reply.get("ResponseCode")) == "0" and checkout {
            LOG.info(
                "STK push for %s accepted (%s, %s)",
                request.reference,
                checkout,
                masked(request.phone)
            );
            return StkPushResult(
                accepted=True,
                checkout_request_id=str(checkout),
                message=str(reply.get("CustomerMessage", ""))
            );
        }
        code = str(reply.get("errorCode") or reply.get("ResponseCode") or status);
        LOG.warning(
            "STK push for %s refused: HTTP %d, %s", request.reference, status, code
        );
        return StkPushResult(
            accepted=False,
            error_code=code,
            message=str(
                reply.get("errorMessage") or reply.get("ResponseDescription") or ""
            )
        );
    }

    def query(checkout_request_id: str) -> StkStatus {
        body = self._signed();
        body["CheckoutRequestID"] = checkout_request_id;
        for attempt in range(self.retries + 1) {
            try {
                (status, reply) = self._post("/mpesa/stkpushquery/v1/query", body);
            } except (TimeoutError, OSError) as e {
                LOG.warning(
                    "STK query for %s failed (attempt %d): %s",
                    checkout_request_id,
                    attempt + 1,
                    type(e).__name__
                );
                if attempt < self.retries {
                    time.sleep(self.backoff_s * (attempt + 1));
                }
                continue;
            }
            return _query_status(checkout_request_id, status, reply);
        }
        return StkStatus(
            checkout_request_id=checkout_request_id,
            state=PaymentState.UNKNOWN,
            result_text="M-Pesa didn't answer the status query."
        );
    }
}

def _query_status(
    checkout_request_id: str,
    status: int,
    reply: dict[str, any]  # jac:ignore[W1037]
) -> StkStatus {
    if status == 200 and "ResultCode" in reply {
        try {
            code = int(reply["ResultCode"]);
        } except (TypeError, ValueError) {
            code = -1;
        }
        if code >= 0 {
            return StkStatus(
                checkout_request_id=checkout_request_id,
                state=state_for_result(code),
                result_code=code,
                result_text=str(reply.get("ResultDesc", ""))
            );
        }
    }
    if reply.get("errorCode") == PROCESSING {
        return StkStatus(
            checkout_request_id=checkout_request_id,
            state=PaymentState.STK_REQUESTED,
            result_text=str(reply.get("errorMessage", ""))
        );
    }
    LOG.warning(
        "STK query for %s: %s", checkout_request_id, reply.get("errorCode", status)
    );
    return StkStatus(
        checkout_request_id=checkout_request_id,
        state=PaymentState.UNKNOWN,
        result_text=str(reply.get("errorMessage", ""))
    );
}
