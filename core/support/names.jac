"""Names the support modules share (P13.5b, P13.5c), kept apart so none imports another.

REPLY_MAIL: the claims that queue our reply emails, one per email ("<tenant id>|<request
id>|<address>"), written by core/support/requests.jac, sent by core/support/mail.jac,
and counted when late by core/support/health.jac.
"""

glob REPLY_MAIL: str = "support-reply-mail";
