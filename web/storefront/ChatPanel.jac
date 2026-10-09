"""A cinema's own chat on its storefront (P8.4): "Ask <cinema>", then the conversation.

A button at the bottom corner opens a panel covering the whole screen, on a phone and on
a PC (the user's choice, as ChatGPT and Claude do), with the conversation in a centred
column; it's a Sheet, so focus stays inside and Escape closes it. The visitor types or taps a
suggestion; the server's cinema_chat answers with words and cards (chat_cards.jac) built
from its tools' results. New replies are announced once (the log is a polite live
region) and a "Thinking…" status shows while the cinema's assistant works.

The conversation lasts for the visit: it's kept in sessionStorage per cinema, so it
survives moving between the storefront's pages, and goes when the tab closes. The server
treats what the client sends back as untrusted (core/agent/agent_api.jac). Booking (P8.5)
happens in the booking card, the storefront's own checkout: the assistant can only open
it and suggest seats.
"""

import from react { useState, useEffect, useRef }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { AiChat02Icon, SentIcon, Cancel01Icon }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from ...components.ui.sheet {
    Sheet,
    SheetTrigger,
    SheetContent,
    SheetTitle,
    SheetDescription,
    SheetClose
}
import from core.agent.agent_api { cinema_chat }
import from .checkout_rules { visitor_id }
import from .chat_cards { ChatCard }

glob MESSAGE_MAX: int = 1000,
     # The conversation's column: the whole width on a phone, centred and readable on a
     # PC (the panel itself covers the screen, as ChatGPT's and Claude's do).
     COLUMN: str = "mx-auto w-full max-w-3xl",
     SUGGESTIONS: list[str] = [
         "What's on tonight?",
         "What's showing this weekend?",
         "Anything good for kids?",
         "Book two seats for tonight"
     ];

def:pub chat_key(slug: str) -> str {
    return f"africinemas:chat:{slug}";
}

def:pub history_of(messages: list[dict[str, any]]) -> list[dict[str, str]] {  # jac:ignore[W1037]
    # What the server needs of the conversation: who said what, without the cards.
    return [
        {"role": m["role"], "content": m["content"]}
        for m in messages
        if m["role"] == "user" or m["role"] == "assistant"
    ];
}

def _kept(slug: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        raw = win.sessionStorage.getItem(chat_key(slug));
        if raw {
            found: any = JSON.parse(raw);  # jac:ignore[W1037,W2001]
            if Array.isArray(found) {  # jac:ignore[W2001]
                return found;
            }
        }
    } except Exception {
        return [];
    }
    return [];
}

def _keep(slug: str, messages: list[dict[str, any]]) {  # jac:ignore[W1037]
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        win.sessionStorage.setItem(chat_key(slug), JSON.stringify(messages));  # jac:ignore[W2001]
    } except Exception {
        return;
    }
}

def Suggestion(text: str, on_pick: any) -> JsxElement {  # jac:ignore[W1037]
    return
        <Button
            type="button"
            variant="outline"
            data-testid="chat-suggestion"
            className="min-h-11 rounded-full px-4"
            onClick={lambda { on_pick(text); }}
        >
            {text}
        </Button>;
}

def Message(message: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    mine: bool = message["role"] == "user";
    cards: list[dict[str, any]] = message["cards"] or [];  # jac:ignore[W1037]
    return
        <li
            data-testid={"chat-mine" if mine else "chat-reply"}
            className={"flex flex-col gap-3 "
                + ("items-end" if mine else "items-stretch")}
        >
            <p
                className={"max-w-[85%] rounded-2xl px-4 py-2.5 whitespace-pre-wrap "
                    + (
                        "bg-primary text-primary-foreground"
                            if mine
                            else "w-fit bg-muted text-foreground"
                    )}
            >
                <span className="sr-only">{"You: " if mine else "Assistant: "}</span>
                {message["content"]}
            </p>
            {[<ChatCard key={i} card={c}/> for (i, c) in enumerate(cards)]}
        </li>;
}

def:pub ChatLauncher(slug: str, cinema: str) -> JsxElement {
    [open, set_open] = useState(False);
    [messages, set_messages] = useState([]);
    [draft, set_draft] = useState("");
    [busy, set_busy] = useState(False);
    [failed, set_failed] = useState("");
    end = useRef(None);

    def restore {
        set_messages(_kept(slug));
    }
    useEffect(restore, [slug]);

    def follow {
        # Keeps the newest message in view.
        target: any = end.current;  # jac:ignore[W1037]
        if target {
            target.scrollIntoView({"block": "end"});
        }
    }
    useEffect(follow, [messages, busy, open]);

    async def send(text: str) {
        said = text.strip()[:MESSAGE_MAX];
        if busy or not said {
            return;
        }
        before: list[dict[str, any]] = messages;  # jac:ignore[W1037]
        mine = before + [{"role": "user", "content": said, "cards": []}];
        set_messages(mine);
        set_draft("");
        set_failed("");
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await cinema_chat(slug, said, history_of(before), visitor_id());
        } except Exception as e {
            console.warn("chat failed", e);
        }
        set_busy(False);
        if not got or not got["ok"] {
            # Not sent: the visitor's words go back in the box to try again.
            set_messages(before);
            set_draft(said);
            set_failed("Your message didn't go through. Try again.");
            return;
        }
        answered = mine
            + [{"role": "assistant", "content": got["reply"], "cards": got["cards"]}];
        set_messages(answered);
        _keep(slug, answered);
    }

    def typed(event: any) {  # jac:ignore[W1037]
        set_draft(event.target.value);
    }

    def submit(event: any) {  # jac:ignore[W1037]
        event.preventDefault();
        send(draft);
    }

    shown: list[dict[str, any]] = messages;  # jac:ignore[W1037]
    return
        <Sheet open={open} onOpenChange={set_open}>
            <SheetTrigger asChild={True}>
                <Button
                    type="button"
                    data-testid="chat-open"
                    className="fixed right-4 bottom-[max(1rem,env(safe-area-inset-bottom))] z-30 min-h-12 gap-2 rounded-full px-5 shadow-lg"
                >
                    <HugeiconsIcon
                        icon={AiChat02Icon}
                        strokeWidth={2}
                        aria-hidden="true"
                    />
                    {f"Ask {cinema}"}
                </Button>
            </SheetTrigger>
            <SheetContent
                side="right"
                showCloseButton={False}
                data-testid="chat-panel"
                className={"gap-0 p-0 data-[side=right]:w-full data-[side=right]:border-l-0 data-[side=right]:sm:max-w-none "
                    + "data-[side=right]:data-open:slide-in-from-right-0 data-[side=right]:data-closed:slide-out-to-right-0"}
            >
                <div className="border-b">
                    <div
                        className={COLUMN
                            + " flex items-start justify-between gap-3 p-4"}
                    >
                        <div className="flex flex-col gap-1">
                            <SheetTitle className="text-base font-semibold">
                                {f"Ask {cinema}"}
                            </SheetTitle>
                            <SheetDescription className="text-sm text-muted-foreground">
                                {f"Answers come from {cinema}'s programme. Book and pay right here: you choose the seats and pay with your own M-Pesa PIN."}
                            </SheetDescription>
                        </div>
                        <SheetClose asChild={True}>
                            <Button
                                type="button"
                                variant="ghost"
                                className="size-11 shrink-0"
                                aria-label="Close the chat"
                            >
                                <HugeiconsIcon
                                    icon={Cancel01Icon}
                                    strokeWidth={2}
                                    aria-hidden="true"
                                />
                            </Button>
                        </SheetClose>
                    </div>
                </div>
                <div className="flex-1 overflow-y-auto">
                    <div className={COLUMN + " p-4"}>
                        {len(shown) == 0
                            and <div className="flex flex-col gap-3">
                                <p className="text-muted-foreground">
                                    {f"Ask about films, showtimes or seats at {cinema}."}
                                </p>
                                <div className="flex flex-wrap gap-2">
                                    {[
                                        <Suggestion key={s} text={s} on_pick={send}/>
                                        for s in SUGGESTIONS
                                    ]}
                                </div>
                            </div>}
                        <ol
                            data-testid="chat-log"
                            role="log"
                            aria-live="polite"
                            aria-label="Conversation"
                            aria-busy={"true" if busy else "false"}
                            className="flex flex-col gap-4"
                        >
                            {[
                                <Message key={i} message={m}/>
                                for (i, m) in enumerate(shown)
                            ]}
                        </ol>
                        {busy
                            and <p
                                role="status"
                                data-testid="chat-thinking"
                                className="mt-4 flex items-center gap-2 text-sm text-muted-foreground"
                            >
                                <Spinner className="size-4"/>
                                Thinking…
                            </p>}
                        <div ref={end}></div>
                    </div>
                </div>
                <div className="border-t">
                    <form
                        onSubmit={submit}
                        className={COLUMN
                            + " flex flex-col gap-2 p-4 pb-[max(1rem,env(safe-area-inset-bottom))]"}
                    >
                        {failed
                            and <p role="alert" className="text-sm text-destructive">
                                {failed}
                            </p>}
                        <Label htmlFor="chat-message" className="sr-only">
                            Your message
                        </Label>
                        <div className="flex gap-2">
                            <Input
                                id="chat-message"
                                data-testid="chat-input"
                                value={draft}
                                maxLength={MESSAGE_MAX}
                                autoComplete="off"
                                placeholder="Ask about films or showtimes"
                                onChange={typed}
                                className="min-h-11 min-w-0 flex-1"
                            />
                            <Button
                                type="submit"
                                data-testid="chat-send"
                                disabled={busy}
                                className="min-h-11 gap-2 px-4"
                            >
                                <HugeiconsIcon
                                    icon={SentIcon}
                                    strokeWidth={2}
                                    aria-hidden="true"
                                />
                                Send
                            </Button>
                        </div>
                    </form>
                </div>
            </SheetContent>
        </Sheet>;
}
