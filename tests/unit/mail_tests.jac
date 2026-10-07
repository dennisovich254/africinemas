"""P6.3a: email addresses, the ticket email and the mail sender.

core/notify/addresses.jac checks an address as the pay form does and masks it for the
screen. core/notify/ticket_mail.jac writes the ticket email: one QR image per seat shown
inside the HTML (cid:), the references, the showtime in the cinema's local time and the
ticket link, from the cinema's name on our address. core/notify/mailer.jac sends it over
SMTP when AFRICINEMAS_SMTP_HOST is set, and otherwise drops it in the development outbox
(a .eml file per message, and OUTBOX for tests), never sending real mail.
"""

import os;
import tempfile;
import unittest.mock;
import from pathlib { Path }
import from email { message_from_string, policy }
import from core.notify.addresses { email_problem, clean_email, masked_email }
import from core.notify.ticket_mail { TicketMail, MailTicket, ticket_mail }
import from core.notify.mailer { OUTBOX, OUTBOX_ENV, SMTP_ENV, FROM_ENV, send }
import from core.booking.ticket_codes { KEY_ENV, qr_payload }

glob KEY: str = "unit-test-ticket-key-0123456789abcdef";

def _mail -> TicketMail {
    before = os.environ.get(KEY_ENV);
    os.environ[KEY_ENV] = KEY;
    try {
        tickets = [
            MailTicket(
                seat_label=seat, ticket_name="Adult", reference=ref, qr=qr_payload(ref)
            )
            for (seat, ref) in [
                ("A1", "7K2M-9QXR-4HJN-P3WD"),
                ("A2", "8L3N-2RYS-5JKP-Q4XE")
            ]
        ];
    } finally {
        if before is None {
            os.environ.pop(KEY_ENV, None);
        } else {
            os.environ[KEY_ENV] = before;
        }
    }
    return TicketMail(
        to="anna@example.com",
        cinema_name="Nova Cinemas",
        reply_to="hello@nova.example",
        movie_title="Rafiki",
        starts_at="2026-10-09T15:15:00+00:00",
        timezone="Africa/Nairobi",
        place="Westgate · Screen 1",
        order_reference="AB12CD34EF",
        link="https://africinemas.example/c/nova/tickets/abc123",
        tickets=tickets
    );
}

test "an address is checked as the pay form checks it, and tidied" {
    assert email_problem("anna@example.com") == "";
    assert email_problem("  Anna.K+films@Mail.Example.co.ke ") == "";
    for bad in [
        "",
        "anna",
        "anna@",
        "@example.com",
        "anna@example",
        "an na@example.com",
        "a@b@example.com"
    ] {
        assert email_problem(bad) != "" , bad;
    }
    assert email_problem("a" * 250 + "@example.com") != "";
    assert clean_email("  Anna@Example.COM ") == "Anna@example.com";
}

test "an address shown on screen is masked" {
    assert masked_email("dennis@gmail.com") == "d*****@gmail.com";
    assert masked_email("al@x.co") == "a*@x.co";
    assert masked_email("a@x.co") == "a@x.co";
}

test "the ticket email: from the cinema on our address, one inline QR image per seat" {
    mail = ticket_mail(_mail(), "tickets@africinemas.example");
    assert mail.sender == "Nova Cinemas <tickets@africinemas.example>";
    assert mail.reply_to == "hello@nova.example";
    assert mail.to == "anna@example.com";
    assert "Rafiki" in mail.subject and "Nova Cinemas" in mail.subject;
    # 15:15 UTC is 18:15 in Nairobi.
    assert "18:15" in mail.text and "Friday 9 October 2026" in mail.text;
    for ref in ["7K2M-9QXR-4HJN-P3WD", "8L3N-2RYS-5JKP-Q4XE", "AB12CD34EF"] {
        assert ref in mail.text and ref in mail.html , ref;
    }
    assert "https://africinemas.example/c/nova/tickets/abc123" in mail.text;
    assert "https://africinemas.example/c/nova/tickets/abc123" in mail.html;
    assert len(mail.images) == 2;
    for image in mail.images {
        assert image.content.startswith(b"\x89PNG") , image.filename;
        assert f'src="cid:{image.content_id}"' in mail.html;
    }
    assert "Tickets by AfriCinemas" in mail.text;
}

test "the ticket email escapes what the cinema typed" {
    data = _mail();
    data.movie_title = "<script>x</script>";
    mail = ticket_mail(data, "tickets@africinemas.example");
    assert "<script>" not in mail.html;
    assert "&lt;script&gt;" in mail.html;
}

test "without SMTP settings, mail goes to the development outbox, never out" {
    outbox = tempfile.mkdtemp(prefix="africinemas-outbox-");
    saved = {n: os.environ.get(n) for n in [SMTP_ENV, OUTBOX_ENV, FROM_ENV]};
    os.environ.pop(SMTP_ENV, None);
    os.environ[OUTBOX_ENV] = outbox;
    os.environ[FROM_ENV] = "tickets@africinemas.example";
    OUTBOX.clear();
    try {
        with unittest.mock.patch("smtplib.SMTP") as smtp {
            assert send(ticket_mail(_mail(), "tickets@africinemas.example"));
            assert not smtp.called;
        }
        assert len(OUTBOX) == 1 and OUTBOX[0].to == "anna@example.com";
        files = list(Path(outbox).glob("*.eml"));
        assert len(files) == 1;
        parsed = message_from_string(files[0].read_text(), policy=policy.default);
        assert parsed["To"] == "anna@example.com";
        assert parsed["Reply-To"] == "hello@nova.example";
        images = [
            p
            for p in parsed.walk()
            if p.get_content_type() == "image/png"
        ];
        assert len(images) == 2 and all([p["Content-ID"] for p in images]);
    } finally {
        OUTBOX.clear();
        for (n, v) in saved.items() {
            os.environ.pop(n, None);
            if v is not None {
                os.environ[n] = v;
            }
        }
    }
}

test "with an SMTP host, mail is sent over SMTP with the same message" {
    saved = {n: os.environ.get(n) for n in [SMTP_ENV, OUTBOX_ENV]};
    os.environ[SMTP_ENV] = "smtp.example.com";
    OUTBOX.clear();
    try {
        with unittest.mock.patch("smtplib.SMTP") as smtp_cls {
            assert send(ticket_mail(_mail(), "tickets@africinemas.example"));
            smtp = smtp_cls.return_value.__enter__.return_value;
            assert smtp.send_message.called;
            sent = smtp.send_message.call_args.args[0];
            assert sent["From"] == "Nova Cinemas <tickets@africinemas.example>";
            assert sent["To"] == "anna@example.com";
        }
        assert OUTBOX == [];
    } finally {
        for (n, v) in saved.items() {
            os.environ.pop(n, None);
            if v is not None {
                os.environ[n] = v;
            }
        }
    }
}
