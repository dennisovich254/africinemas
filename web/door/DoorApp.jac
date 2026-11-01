"""The installed scanner at /door/<cinema> (plan 17.2b; docs/specs/offline-scanner.md).

Trial S1 (§19): the page proves the offline shell before the scanner is built on it.
It registers the scanner's service worker (core/door/shell.jac) and hands it the files
this page already loaded, so the next launch with no connection opens from the cache.
It shows whether that worked (the worker in control, the version kept, storage that
lasts, IndexedDB writing and reading, and the hashing test vector of §7.2), and checks
codes against a test ticket kept in IndexedDB, the way the scanner will offline.

It runs outside the back office (no sign-in check, no site lookup), so nothing here
asks the server for anything it can't do without.
"""

import from react { useState, useEffect }
import from ..theme.ThemeProvider { ThemeProvider }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ..backoffice.ScannerSection { Camera }

glob DB_NAME: str = "africinemas-door",
     DB_VERSION: int = 1,
     STORE: str = "trial",
     # §7.2's test vector: a device whose hashing agrees with the server's gets this.
     VECTOR_SALT: str = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
     VECTOR_REF: str = "7K2M9QXR4HJNP3WD",
     VECTOR_HASH: str = "4e73291af7471910ef674eb1656b2a4d644badae5e333a879ddefdd028cfd08c",
     ALPHABET: str = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

def:pub normalize(code: str) -> str {
    # The 16-character reference a QR ("TKT1.<ref>.<sig>") or typed code names; "" if
    # it doesn't name one (§7.2, R6).
    text = code.strip();
    if text.startswith("TKT1.") {
        parts = text.split(".");
        text = parts[1] if len(parts) == 3 else "";
    }
    found = text.upper().replace("-", "").replace(" ", "");
    if len(found) != 16 {
        return "";
    }
    for ch in found {
        if ch not in ALPHABET {
            return "";
        }
    }
    return found;
}

async def:pub door_hash(salt: str, reference: str) -> str {
    # §7.2: lowercase hex SHA-256 of "door1|<salt>|<reference>".
    win: any = window;  # jac:ignore[W1037,W2001]
    data: any = new(win.TextEncoder).encode(f"door1|{salt}|{reference}");  # jac:ignore[W1037]
    digest: any = await win.crypto.subtle.digest("SHA-256", data);  # jac:ignore[W1037]
    out: list[str] = [];
    for b in win.Array.from(new(win.Uint8Array, digest)) {  # jac:ignore[W6001,W6002] client-only bytes to hex
        out.append(b.toString(16).padStart(2, "0"));  # jac:ignore[W6002]
    }
    return "".join(out);
}

def _db -> any {  # jac:ignore[W1037]
    # The scanner's IndexedDB, opened (a Promise).
    win: any = window;  # jac:ignore[W1037,W2001]
    def opener(resolve: any, reject: any) {  # jac:ignore[W1037]
        asked: any = win.indexedDB.open(DB_NAME, DB_VERSION);  # jac:ignore[W1037]
        def upgrade {
            db: any = asked.result;  # jac:ignore[W1037]
            if not db.objectStoreNames.contains(STORE) {
                db.createObjectStore(STORE);
            }
        }
        asked.onupgradeneeded = upgrade;
        asked.onsuccess = lambda { resolve(asked.result); };
        asked.onerror = lambda { reject(asked.error); };
    }
    return new(win.Promise, opener);  # jac:ignore[W2001,W6001] IndexedDB has no async API
}

async def _put(key: str, value: any) {  # jac:ignore[W1037]
    win: any = window;  # jac:ignore[W1037,W2001]
    db: any = await _db();  # jac:ignore[W1037]
    def writer(resolve: any, reject: any) {  # jac:ignore[W1037]
        tx: any = db.transaction(STORE, "readwrite");  # jac:ignore[W1037]
        tx.objectStore(STORE).put(value, key);
        tx.oncomplete = lambda { resolve(True); };
        tx.onerror = lambda { reject(tx.error); };
    }
    await new(win.Promise, writer);  # jac:ignore[W2001,W6001]
}

async def _get(key: str) -> any {  # jac:ignore[W1037]
    win: any = window;  # jac:ignore[W1037,W2001]
    db: any = await _db();  # jac:ignore[W1037]
    def reader(resolve: any, reject: any) {  # jac:ignore[W1037]
        asked: any = db.transaction(STORE, "readonly").objectStore(STORE).get(key);  # jac:ignore[W1037]
        asked.onsuccess = lambda { resolve(asked.result); };
        asked.onerror = lambda { reject(asked.error); };
    }
    return await new(win.Promise, reader);  # jac:ignore[W2001,W6001]
}

def _head_links {
    # The scanner's manifest and icon, so it installs as its own app.
    doc: any = document;  # jac:ignore[W1037,W2001]
    if doc.querySelector('link[rel="manifest"]') {
        return;
    }
    for (rel, href) in [
        ("manifest", "/door/manifest.webmanifest"),
        ("apple-touch-icon", "/static/door/icon-192.png")
    ] {
        link: any = doc.createElement("link");  # jac:ignore[W1037,W6001]
        link.rel = rel;
        link.href = href;
        doc.head.appendChild(link);
    }
}

def _loaded_files -> list[str] {
    # The /static/ files this page has loaded: the bundle, styles, fonts, the QR worker.
    win: any = window;  # jac:ignore[W1037,W2001]
    found: list[str] = [];
    for res in win.performance.getEntriesByType("resource") {
        url: any = new(win.URL, res.name);  # jac:ignore[W1037]
        if url.origin == win.location.origin and url.pathname.startsWith("/static/") {
            found.append(url.pathname + url.search);
        }
    }
    return found;
}

def _bundle_version(files: list[str]) -> str {
    # The client bundle's hash, from /static/client.js?hash=…: this version of the app.
    for f in files {
        if f.startswith("/static/client.js?hash=") {
            return f.split("hash=")[1];
        }
    }
    return "";
}

async def _keep_shell -> dict[str, any] {  # jac:ignore[W1037]
    # Registers the worker and asks it to keep this version's files.
    win: any = window;  # jac:ignore[W1037,W2001]
    nav: any = win.navigator;  # jac:ignore[W1037]
    if not nav.serviceWorker {
        return {"ok": False, "error": "This browser has no service workers."};
    }
    await nav.serviceWorker.register("/door/sw.js", {"scope": "/door/"});
    ready: any = await nav.serviceWorker.ready;  # jac:ignore[W1037]
    files = _loaded_files();
    version = _bundle_version(files);
    if not version {
        return {"ok": False, "error": "Couldn't tell this version of the app."};
    }
    channel: any = new(win.MessageChannel);  # jac:ignore[W1037]
    def waiter(resolve: any) {  # jac:ignore[W1037]
        channel.port1.onmessage = lambda (e: any) { resolve(e.data); };  # jac:ignore[W1037]
    }
    answer: any = new(win.Promise, waiter);  # jac:ignore[W1037,W2001,W6001]
    ready.active.postMessage(
        {
            "type": "keep",
            "version": version,
            "urls": files,
            "shell": win.location.pathname
        },
        [channel.port2]
    );
    return await answer;
}

def Check(label: str, state: str, detail: str = "") -> JsxElement {
    # One line of the readiness list: "yes", "no", or "…" while it's being checked.
    mark = {"yes": "✓", "no": "✗"}.get(state, "…");
    return
        <li
            className="flex items-baseline gap-3 py-1.5"
            data-testid="door-check"
            data-state={state}
        >
            <span aria-hidden="true" className="w-4 font-semibold">{mark}</span>
            <span className="flex flex-col">
                <span>
                    {label}
                    <span className="sr-only">{f": {state}"}</span>
                </span>
                {detail
                    and <span className="text-xs text-muted-foreground">{detail}</span>}
            </span>
        </li>;
}

def:pub DoorApp -> JsxElement {
    win: any = window;  # jac:ignore[W1037,W2001]
    slug: str = win.location.pathname.split("/")[2] or "";
    [online, set_online] = useState(bool(win.navigator.onLine));
    [controlled, set_controlled] = useState(
        bool(win.navigator.serviceWorker and win.navigator.serviceWorker.controller)
    );
    [kept, set_kept] = useState("");
    [kept_detail, set_kept_detail] = useState("");
    [persisted, set_persisted] = useState("");
    [db_ok, set_db_ok] = useState("");
    [vector_ok, set_vector_ok] = useState("");
    [has_test, set_has_test] = useState(False);
    [code, set_code] = useState("");
    [result, set_result] = useState(None);

    async def start {
        _head_links();
        try {
            got: any = await _keep_shell();  # jac:ignore[W1037]
            if got["ok"] {
                set_kept("yes");
                set_kept_detail(f"Version {got['version'][:8]}, {got['count']} files");
            } else {
                set_kept("no");
                set_kept_detail(got["error"] or "Not kept");
            }
        } except Exception as e {
            set_kept("no");
            set_kept_detail(
                "The app's files couldn't be kept (offline on first visit?)"
            );
            console.warn("door shell failed", e);
        }
        set_controlled(
            bool(win.navigator.serviceWorker and win.navigator.serviceWorker.controller)
        );
        try {
            storage: any = win.navigator.storage;  # jac:ignore[W1037]
            lasting: bool = bool(await storage.persist())
                if storage and storage.persist
                else False;
            set_persisted("yes" if lasting else "no");
        } except Exception {
            set_persisted("no");
        }
        try {
            stamp = new(win.Date).toISOString();  # jac:ignore[W2001]
            await _put("write-test", stamp);
            set_db_ok("yes" if (await _get("write-test")) == stamp else "no");
            set_has_test(bool(await _get("test-ticket")));
        } except Exception as e {
            set_db_ok("no");
            console.warn("door storage failed", e);
        }
        try {
            set_vector_ok(
                "yes"
                    if (await door_hash(VECTOR_SALT, VECTOR_REF)) == VECTOR_HASH
                    else "no"
            );
        } except Exception {
            set_vector_ok("no");
        }
    }

    def first -> any {  # jac:ignore[W1037]
        start();
        on = lambda { set_online(True); };
        off = lambda { set_online(False); };
        win.addEventListener("online", on);
        win.addEventListener("offline", off);
        return lambda {
            win.removeEventListener("online", on);
            win.removeEventListener("offline", off);
        };
    }
    useEffect(first, []);

    async def prepare_test {
        # A test ticket kept the way the scanner keeps the pack: by hash, with its seat.
        h = await door_hash(VECTOR_SALT, VECTOR_REF);
        await _put(
            "test-ticket",
            {"salt": VECTOR_SALT, "h": h, "seat": "F7", "ticket_name": "Adult (test)"}
        );
        set_has_test(True);
    }

    async def check(text: str) {
        found = normalize(text);
        if not found {
            set_result({"ok": False, "words": "This isn't a ticket code."});
            return;
        }
        sample: any = await _get("test-ticket");  # jac:ignore[W1037]
        if not sample {
            set_result({"ok": False, "words": "No test ticket on this device yet."});
            return;
        }
        if (await door_hash(sample["salt"], found)) == sample["h"] {
            set_result(
                {
                    "ok": True,
                    "words": f"Seat {sample['seat']} · {sample['ticket_name']}"
                }
            );
        } else {
            set_result({"ok": False, "words": "Not on this device's list."});
        }
    }

    shown: any = result;  # jac:ignore[W1037]
    return
        <ThemeProvider surface="backoffice">
            <main
                className="mx-auto flex min-h-svh w-full max-w-md flex-col gap-5 p-4"
                data-testid="door-app"
            >
                <header className="flex items-center justify-between gap-3">
                    <h1 className="text-xl font-semibold">Scanner</h1>
                    <span
                        role="status"
                        data-testid="door-online"
                        data-online={"true" if online else "false"}
                        className={"rounded-full px-3 py-1 text-sm font-medium "
                            + ("bg-emerald-500/15" if online else "bg-amber-500/20")}
                    >
                        {"Online" if online else "Offline"}
                    </span>
                </header>
                <p className="text-sm text-muted-foreground">
                    {f"Trial of the offline scanner for {slug}."
                        if slug
                        else "Trial of the offline scanner."}{" Open it once online, install it to the home screen, then try it in airplane mode."}
                </p>
                <section
                    aria-labelledby="ready-title"
                    className="rounded-lg border bg-card p-3"
                >
                    <h2 id="ready-title" className="mb-1 font-medium">
                        Ready for offline
                    </h2>
                    <ul className="text-sm">
                        <Check
                            label="The app's files are kept on this device"
                            state={kept}
                            detail={kept_detail}
                        />
                        <Check
                            label="This page opened from the scanner's worker"
                            state={"yes" if controlled else ("no" if kept else "")}
                            detail={""
                                if controlled
                                else "Close and reopen the scanner once."}
                        />
                        <Check
                            label="Storage that lasts"
                            state={persisted}
                            detail="Install the app if this says no."
                        />
                        <Check label="Saving and reading on this device" state={db_ok}/>
                        <Check
                            label="Ticket checks agree with the server"
                            state={vector_ok}
                        />
                    </ul>
                </section>
                <section
                    aria-labelledby="test-title"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-3"
                >
                    <h2 id="test-title" className="font-medium">Try a scan</h2>
                    {not has_test
                        and <Button
                            className="min-h-11"
                            data-testid="door-prepare"
                            onClick={prepare_test}
                        >
                            Keep a test ticket on this device
                        </Button>}
                    {has_test
                        and <p
                            className="text-sm text-muted-foreground"
                            data-testid="door-test-kept"
                        >
                            Test ticket kept: 7K2M-9QXR-4HJN-P3WD (seat F7).
                        </p>}
                    <form
                        className="flex gap-2"
                        onSubmit={lambda (e: any) {  # jac:ignore[W1037]
                            e.preventDefault();
                            check(code);
                        }}
                    >
                        <label htmlFor="door-code" className="sr-only">
                            Ticket reference
                        </label>
                        <Input
                            id="door-code"
                            value={code}
                            placeholder="Ticket reference"
                            autoComplete="off"
                            className="min-h-11"
                            onChange={lambda (e: any) { set_code(e.target.value); }}  # jac:ignore[W1037]
                        />
                        <Button
                            type="submit"
                            className="min-h-11"
                            data-testid="door-check-code"
                        >
                            Check
                        </Button>
                    </form>
                    <Camera
                        on_code={lambda (c: str) { check(c); }}
                        screening_id="door-trial"
                    />
                    {shown is not None
                        and <p
                            role="status"
                            data-testid="door-result"
                            data-ok={"true" if shown["ok"] else "false"}
                            className={"rounded-md p-3 text-lg font-semibold "
                                + (
                                    "bg-emerald-500/15"
                                        if shown["ok"]
                                        else "bg-destructive/10"
                                )}
                        >
                            {("✓ " if shown["ok"] else "✗ ") + shown["words"]}
                        </p>}
                </section>
            </main>
        </ThemeProvider>;
}
