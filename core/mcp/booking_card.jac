"""The booking card (P8.6b): the MCP App that core/mcp/server.jac serves as ui://africinemas/booking.

book_showtime's result opens it for one showtime, with seats the model may suggest.
Everything after that is the customer's own doing, in the card, through the card's
tools (core/mcp/booking.jac), which the model never sees:

1. Seats: the screen's seat grid; free seats are buttons (44 px or more, with their
   label), suggested ones start chosen. "Hold" holds them (card_hold).
2. Tickets: a ticket type per held seat; the server prices them (card_quote).
   "Continue to pay" places the order (card_order).
3. Pay: phone and email typed here, straight to our server, never to the model;
   "Pay with M-Pesa" sends the prompt (card_pay) and the card asks every few seconds
   how it went (card_status) while the customer enters their PIN on their phone.
4. Booked: the seats, where the tickets were emailed, and "Open your tickets".

Reopened, it picks up where the customer was (card_state). Signed out, it says to sign
in, with a link to book on the website. The shared look and host bridge are in
card_kit.jac: text is only ever set as text, and nothing loads from outside.
"""

import from core.mcp.card_kit { page }

glob BOOKING_CSS: str = """h1 { font-size: 20px; line-height: 1.25; margin: 0; overflow-wrap: anywhere; }
.when { margin: 4px 0 16px; color: var(--muted); }
.screen { text-align: center; font-size: 12px; letter-spacing: 0.2em; color: var(--muted); border-top: 3px solid var(--line); padding-top: 4px; margin: 0 0 12px; }
.grid { display: grid; gap: 6px; overflow-x: auto; padding-bottom: 4px; }
.seat { min-width: 44px; min-height: 44px; padding: 0 4px; font-size: 13px; font-weight: 600; }
.seat[aria-pressed="true"] { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
.seat:disabled { opacity: 0.45; cursor: not-allowed; text-decoration: line-through; }
.gap { min-width: 44px; min-height: 44px; }
.row { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; align-items: center; }
.note { color: var(--muted); font-size: 14px; margin: 8px 0 0; }
.problem { color: var(--color-text-danger, #b42318); margin: 12px 0 0; font-weight: 600; }
.field { display: flex; flex-direction: column; gap: 4px; margin-top: 12px; }
.field label { font-weight: 600; font-size: 14px; }
.field input, .field select { font: inherit; min-height: 44px; padding: 0 12px; border: 1px solid var(--line); border-radius: var(--radius); background: var(--bg); color: var(--fg); }
.total { font-size: 18px; font-weight: 700; margin-top: 16px; }
ul.seats { padding-left: 20px; margin: 8px 0 0; }
""",
     BOOKING_JS: str = """  var appName = "africinemas-booking";
  var booking = null;
  var chosen = [];
  var view = null;
  var orderKey = "";
  var payKey = "";
  var polls = 0;

  function randomKey(prefix) {
    var bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    return prefix + Array.prototype.map.call(bytes, function (b) { return ("0" + b.toString(16)).slice(-2); }).join("");
  }
  function money(cents, currency) {
    var amount = (Number(cents) || 0) / 100;
    return (currency || "") + " " + amount.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  }
  function where() { return { cinema: booking.cinema_slug, showtime_id: booking.showtime_id }; }
  function ask(name, extra) {
    var args = where();
    Object.keys(extra || {}).forEach(function (k) { args[k] = extra[k]; });
    return callTool(name, args).then(function (result) {
      return (result && result.structuredContent) || { ok: false, message: resultText(result, "That didn't work.") };
    });
  }
  function header() {
    var nodes = [el("h1", "", booking.movie)];
    var place = [booking.venue, booking.screen].filter(function (p) { return p; }).join(", ");
    nodes.push(el("p", "when", dayName(booking.starts) + " · " + String(booking.starts).slice(11, 16) + (place ? " · " + place : "")));
    return nodes;
  }
  function problemNode(text) { var p = el("p", "problem", text); p.setAttribute("role", "alert"); return p; }

  function showSeats(problem) {
    var nodes = header();
    nodes.push(el("p", "screen", "SCREEN"));
    var grid = el("div", "grid");
    grid.style.gridTemplateColumns = "repeat(" + view.cols + ", minmax(44px, 1fr))";
    var byPlace = {};
    view.seats.forEach(function (s) { byPlace[s.row + ":" + s.col] = s; });
    for (var r = 0; r < view.rows; r++) {
      for (var c = 0; c < view.cols; c++) {
        var s = byPlace[r + ":" + c];
        if (!s) { grid.appendChild(el("span", "gap")); continue; }
        grid.appendChild(seatButton(s));
      }
    }
    nodes.push(grid);
    nodes.push(el("p", "note", chosen.length > 0 ? "Chosen: " + chosen.join(", ") : "Tap the seats you want."));
    if (problem) { nodes.push(problemNode(problem)); }
    var row = el("div", "row");
    var hold = button(chosen.length > 0 ? "Hold " + chosen.length + (chosen.length > 1 ? " seats" : " seat") : "Choose seats", true, function () {
      if (chosen.length === 0) { return; }
      ask("card_hold", { seats: chosen }).then(function (got) {
        if (!got.ok) { refresh(got.message); return; }
        refresh("");
      });
    });
    hold.disabled = chosen.length === 0;
    row.appendChild(hold);
    nodes.push(row);
    show(nodes);
  }
  function seatButton(s) {
    var free = s.state === "available" || s.mine;
    var b = button(s.label, false, function () {
      var at = chosen.indexOf(s.label);
      if (at >= 0) { chosen.splice(at, 1); } else if (chosen.length < 10) { chosen.push(s.label); }
      showSeats("");
    });
    b.className = "seat";
    b.setAttribute("aria-pressed", chosen.indexOf(s.label) >= 0 ? "true" : "false");
    b.setAttribute("aria-label", "Seat " + s.label + (free ? "" : ", taken"));
    b.disabled = !free;
    return b;
  }

  function showTickets(problem) {
    var nodes = header();
    var seats = view.hold.seats;
    var picks = {};
    var total = el("p", "total", "");
    function items() { return seats.map(function (label) { return { seat_label: label, ticket_type: picks[label] }; }); }
    function price() {
      ask("card_quote", { items: items() }).then(function (got) {
        total.textContent = got.ok ? "Total: " + money(got.total, got.currency) : got.message;
        reportSize();
      });
    }
    nodes.push(el("p", "note", "Held for you: " + seats.join(", ") + ". Choose a ticket for each seat."));
    seats.forEach(function (label) {
      var field = el("div", "field");
      var id = "type-" + label;
      var tag = el("label", "", "Seat " + label);
      tag.setAttribute("for", id);
      var pick = el("select");
      pick.id = id;
      view.ticket_types.forEach(function (t) {
        var option = el("option", "", t.name);
        option.value = t.code;
        pick.appendChild(option);
      });
      picks[label] = view.ticket_types.length > 0 ? view.ticket_types[0].code : "";
      pick.addEventListener("change", function () { picks[label] = pick.value; price(); });
      field.appendChild(tag);
      field.appendChild(pick);
      nodes.push(field);
    });
    nodes.push(total);
    if (problem) { nodes.push(problemNode(problem)); }
    var row = el("div", "row");
    row.appendChild(button("Continue to pay", true, function () {
      if (!orderKey) { orderKey = randomKey("card-"); }
      ask("card_order", { items: items(), key: orderKey }).then(function (got) {
        if (!got.ok) { showTickets(got.message); return; }
        refresh("");
      });
    }));
    nodes.push(row);
    show(nodes);
    price();
  }

  function showPay(problem) {
    var nodes = header();
    nodes.push(el("p", "total", "To pay: " + money(view.order.total_cents, view.order.currency)));
    nodes.push(el("p", "note", "Seats " + view.order.seats.join(", ") + ". Your phone gets an M-Pesa prompt: enter your PIN there."));
    var phoneField = el("div", "field");
    var phoneLabel = el("label", "", "M-Pesa phone number");
    phoneLabel.setAttribute("for", "phone");
    var phone = el("input");
    phone.id = "phone"; phone.type = "tel"; phone.inputMode = "tel"; phone.autocomplete = "tel"; phone.placeholder = "07XX XXX XXX";
    phoneField.appendChild(phoneLabel); phoneField.appendChild(phone);
    var emailField = el("div", "field");
    var emailLabel = el("label", "", "Email for your tickets");
    emailLabel.setAttribute("for", "email");
    var email = el("input");
    email.id = "email"; email.type = "email"; email.inputMode = "email"; email.autocomplete = "email";
    emailField.appendChild(emailLabel); emailField.appendChild(email);
    nodes.push(phoneField); nodes.push(emailField);
    if (problem) { nodes.push(problemNode(problem)); }
    var row = el("div", "row");
    row.appendChild(button("Pay with M-Pesa", true, function () {
      if (!payKey) { payKey = randomKey("pay-"); }
      ask("card_pay", { phone: phone.value, email: email.value, key: payKey }).then(function (got) {
        if (!got.ok) { showPay(got.message); return; }
        polls = 0;
        showPaying(got.message);
      });
    }));
    nodes.push(row);
    show(nodes);
  }

  function showPaying(text) {
    var nodes = header();
    var status = el("p", "note", text || "Check your phone and enter your M-Pesa PIN.");
    status.setAttribute("role", "status");
    nodes.push(status);
    show(nodes);
    window.setTimeout(checkPayment, 3000);
  }
  function checkPayment() {
    polls += 1;
    ask("card_status", {}).then(function (got) {
      if (got.ok && got.state === "success") { showBooked(got); return; }
      if (got.ok && (got.state === "failed" || got.state === "cancelled" || got.state === "expired")) {
        payKey = "";
        refresh(got.message || "The payment didn't go through. Try again.");
        return;
      }
      if (polls < 40) { window.setTimeout(checkPayment, 3000); } else { showPaying("Still waiting for M-Pesa. If you paid, your tickets will be emailed."); }
    });
  }

  function showBooked(got) {
    var nodes = header();
    nodes.push(el("p", "total", "You're booked"));
    var list = el("ul", "seats");
    got.seats.forEach(function (s) { list.appendChild(el("li", "", "Seat " + s)); });
    nodes.push(list);
    if (got.email) { nodes.push(el("p", "note", "Tickets were emailed to " + got.email + ".")); }
    if (got.tickets_url) {
      var row = el("div", "row");
      row.appendChild(button("Open your tickets", true, function () { openLink(got.tickets_url); }));
      nodes.push(row);
    }
    show(nodes);
  }

  function showSignedOut() {
    var nodes = header();
    nodes.push(el("p", "note", "To book here, sign in to AfriCinemas in Claude (connect it with sign-in). Or book on the cinema's website."));
    var row = el("div", "row");
    row.appendChild(button("Book on the website", true, function () { openLink(booking.book_url); }));
    nodes.push(row);
    show(nodes);
  }

  // Where the customer is: paid, paying, ordered, held, or choosing.
  function refresh(problem) {
    ask("card_state", {}).then(function (got) {
      if (!got.ok) {
        if (got.code === "sign_in") { showSignedOut(); return; }
        show(header().concat([problemNode(got.message)]));
        return;
      }
      view = got;
      if (got.payment && got.payment.state === "success") {
        ask("card_status", {}).then(function (done) { if (done.ok) { showBooked(done); } });
        return;
      }
      if (got.payment && got.payment.state === "stk_requested") { polls = 0; showPaying(""); return; }
      if (got.order) { showPay(problem); return; }
      if (got.hold) { showTickets(problem); return; }
      showSeats(problem);
    });
  }

  function onToolInput(args) {
    message("Opening the booking…");
  }
  function onToolResult(result) {
    if (result.isError || !result.structuredContent) {
      message(resultText(result, "This showtime can't be booked."));
      return;
    }
    booking = result.structuredContent;
    useBrand(booking.brand);
    chosen = (booking.suggested || []).slice(0, 10);
    if (!booking.signed_in) { showSignedOut(); return; }
    message("Loading the seats…");
    refresh("");
  }
""";

glob BOOKING_HTML: str = page(
         "Booking", "Opening the booking…", BOOKING_CSS, BOOKING_JS
     );
