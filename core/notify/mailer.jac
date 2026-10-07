"""Sending email (P6.3, ADR-0010, ADR-0022).

One AfriCinemas sender for every cinema: AFRICINEMAS_MAIL_FROM is our address, and each
email names the cinema as its display name. With AFRICINEMAS_SMTP_HOST set, mail goes
over SMTP (STARTTLS unless AFRICINEMAS_SMTP_TLS=0; AFRICINEMAS_SMTP_PORT, default 587;
AFRICINEMAS_SMTP_USERNAME and AFRICINEMAS_SMTP_PASSWORD when the server wants a login).
Without it, nothing leaves the machine: each email is written to the development outbox
(AFRICINEMAS_OUTBOX_DIR, default .jac/outbox, one .eml file per message, which any
mail app opens) and kept in OUTBOX for tests, like the M-Pesa simulator.

Jac's built-in emailer can't set Reply-To or attach images (jaseci-labs/jac#9847 adds
them), so this sends with Python's standard library, as ADR-0010 allowed.
"""

import os;
import uuid;
import logging;
import smtplib;
import from pathlib { Path }
import from email.message { EmailMessage }
import from core.clock { now }

glob SMTP_ENV: str = "AFRICINEMAS_SMTP_HOST",
     PORT_ENV: str = "AFRICINEMAS_SMTP_PORT",
     USERNAME_ENV: str = "AFRICINEMAS_SMTP_USERNAME",
     PASSWORD_ENV: str = "AFRICINEMAS_SMTP_PASSWORD",
     TLS_ENV: str = "AFRICINEMAS_SMTP_TLS",
     FROM_ENV: str = "AFRICINEMAS_MAIL_FROM",
     OUTBOX_ENV: str = "AFRICINEMAS_OUTBOX_DIR",
     DEFAULT_FROM: str = "tickets@africinemas.local",
     DEFAULT_OUTBOX: str = ".jac/outbox",
     TIMEOUT_S: float = 15.0,
     logger: logging.Logger = logging.getLogger(__name__);

obj MailImage {
    # A PNG shown inside the HTML body, where src="cid:<content_id>" refers to it.
    has filename: str,
        content: bytes,
        content_id: str;
}

obj OutgoingMail {
    has to: str,
        sender: str,
        subject: str,
        text: str,
        html: str,
        reply_to: str = "",
        images: list[MailImage] = [];
}

glob OUTBOX: list[OutgoingMail] = [];

def from_address -> str {
    return os.environ.get(FROM_ENV, "").strip() or DEFAULT_FROM;
}

def _message(mail: OutgoingMail) -> EmailMessage {
    msg = EmailMessage();
    msg["Subject"] = mail.subject;
    msg["From"] = mail.sender;
    msg["To"] = mail.to;
    if mail.reply_to {
        msg["Reply-To"] = mail.reply_to;
    }
    msg.set_content(mail.text);
    msg.add_alternative(mail.html, subtype="html");
    html_part = msg.get_body(preferencelist=("html", ));
    if html_part is None {
        return msg;
    }
    for image in mail.images {
        html_part.add_related(
            image.content,
            maintype="image",
            subtype="png",
            cid=f"<{image.content_id}>",
            filename=image.filename,
            disposition="inline"
        );
    }
    return msg;
}

def _to_outbox(mail: OutgoingMail, msg: EmailMessage) {
    folder = Path(os.environ.get(OUTBOX_ENV, "").strip() or DEFAULT_OUTBOX);
    folder.mkdir(parents=True, exist_ok=True);
    stamp = now().strftime("%Y%m%dT%H%M%S");
    path = folder / f"{stamp}-{uuid.uuid4().hex[:8]}.eml";
    path.write_text(msg.as_string());
    OUTBOX.append(mail);
    logger.info("email to %s kept in the outbox: %s", mail.to, path);
}

def send(mail: OutgoingMail) -> bool {
    # Sends `mail` (or keeps it in the outbox); False if the SMTP server refused it.
    msg = _message(mail);
    host = os.environ.get(SMTP_ENV, "").strip();
    if not host {
        _to_outbox(mail, msg);
        return True;
    }
    try {
        port = int(os.environ.get(PORT_ENV, "").strip() or "587");
        with smtplib.SMTP(host, port, timeout=TIMEOUT_S) as smtp {
            smtp.ehlo();
            if os.environ.get(TLS_ENV, "").strip() != "0" {
                smtp.starttls();
                smtp.ehlo();
            }
            user = os.environ.get(USERNAME_ENV, "").strip();
            if user {
                smtp.login(user, os.environ.get(PASSWORD_ENV, ""));
            }
            smtp.send_message(msg);
        }
        return True;
    } except Exception as e {
        logger.error("email to %s not sent: %s", mail.to, e);
        return False;
    }
}
