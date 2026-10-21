"""Claude for every AI feature (ADR-0049): one way to ask, one model, one key.

Every model call in AfriCinemas goes through here: the storefront page (pagecode), theme
suggestions (suggest), the brand plan and its figures (brandkit). The model is Claude
Opus 5.5 (`MODEL`, AFRICINEMAS_CLAUDE_MODEL to try another), through the official SDK,
with the key from the environment (ANTHROPIC_API_KEY), never from code.

- Every call is streamed (long answers outlast a plain request's time limit), thinks
  adaptively at the effort the caller asks, and opts into server-side fallbacks
  (`fallbacks: "default"`): a request Claude declines is retried on the model Anthropic
  recommends for its category, inside the same call.
- `ask_json` constrains the answer to a JSON schema (structured outputs) and returns it
  parsed; `ask_text` returns the text. Both raise ClaudeFailed on a provider error, a
  refusal, a cut-off answer or a missing key, so callers fall back on their own terms.

The SDK call lives in the inline Python block: the Jac checker can't read the SDK's HTTP
library (httpx2).
"""

import os;
import json;
import base64;

class ClaudeFailed(RuntimeError) {}

glob MODEL_ENV: str = "AFRICINEMAS_CLAUDE_MODEL",
     MODEL: str = "claude-opus-5-5",
     KEY_ENV: str = "ANTHROPIC_API_KEY",
     FALLBACK_BETA: str = "server-side-fallback-2026-07-01";

::py::
import anthropic as _anthropic


def _answer(model, system, content, max_tokens, timeout, effort, schema, betas):
    # (stop_reason, text, error) for one streamed answer, its thinking left out.
    client = _anthropic.Anthropic(timeout=timeout, max_retries=1)
    output_config = {"effort": effort}
    if schema is not None:
        output_config["format"] = {"type": "json_schema", "schema": schema}
    params = dict(
        model=model,
        max_tokens=max_tokens,
        thinking={"type": "adaptive"},
        output_config=output_config,
        betas=betas,
        fallbacks="default",
        messages=[{"role": "user", "content": content}],
    )
    if system:
        params["system"] = system
    try:
        with client.beta.messages.stream(**params) as stream:
            message = stream.get_final_message()
    except _anthropic.APIError as e:
        return ("error", "", f"{type(e).__name__}: {str(e)[:300]}")
    text = "".join(b.text for b in message.content if b.type == "text")
    return (message.stop_reason, text, "")
::py::



def model_name -> str {
    return os.environ.get(MODEL_ENV) or MODEL;
}

def image_block(picture: bytes, media_type: str = "image/webp") -> dict[str, any] {  # jac:ignore[W1037]
    # A picture (the logo) as a message content block.
    return {
        "type": "image",
        "source": {
            "type": "base64",
            "media_type": media_type,
            "data": base64.b64encode(picture).decode()
        }
    };
}

def text_block(text: str) -> dict[str, str] {
    return {"type": "text", "text": text};
}

def ask_text(
    content: list[dict[str, any]],  # jac:ignore[W1037]
    system: str = "",
    effort: str = "high",
    max_tokens: int = 64000,
    timeout: float = 400.0
) -> str {
    # Claude's answer as text. Raises ClaudeFailed.
    if not os.environ.get(KEY_ENV, "").strip() {
        raise ClaudeFailed(f"no {KEY_ENV}");
    }
    (stop, text, error) = _answer(
        model_name(),
        system,
        content,
        max_tokens,
        timeout,
        effort,
        None,
        [FALLBACK_BETA]
    );
    if error {
        raise ClaudeFailed(error);
    }
    if stop == "refusal" {
        raise ClaudeFailed("the model declined");
    }
    if stop == "max_tokens" {
        raise ClaudeFailed("the answer was cut off");
    }
    return str(text);
}

def ask_json(
    content: list[dict[str, any]],  # jac:ignore[W1037]
    schema: dict[str, any],  # jac:ignore[W1037]
    system: str = "",
    effort: str = "medium",
    max_tokens: int = 16000,
    timeout: float = 120.0
) -> dict[str, any] {  # jac:ignore[W1037]
    # Claude's answer as an object that matches `schema` (structured outputs). Raises
    # ClaudeFailed.
    if not os.environ.get(KEY_ENV, "").strip() {
        raise ClaudeFailed(f"no {KEY_ENV}");
    }
    (stop, text, error) = _answer(
        model_name(),
        system,
        content,
        max_tokens,
        timeout,
        effort,
        schema,
        [FALLBACK_BETA]
    );
    if error {
        raise ClaudeFailed(error);
    }
    if stop == "refusal" {
        raise ClaudeFailed("the model declined");
    }
    if stop == "max_tokens" {
        raise ClaudeFailed("the answer was cut off");
    }
    try {
        found: any = json.loads(str(text));  # jac:ignore[W1037]
    } except ValueError {
        raise ClaudeFailed("the answer wasn't JSON");
    }
    if not isinstance(found, dict) {
        raise ClaudeFailed("the answer wasn't an object");
    }
    return found;
}
