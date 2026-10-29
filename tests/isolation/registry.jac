"""The tenant-isolation registry (plan §2.3): every endpoint the app serves, and its scope.

- "public": needs no login and returns no tenant data.
- "caller": works on the caller's own data only (no tenant selector); `probe`, when
  given, is the request body to call it with.
- "tenant": takes a tenant selector; `probe` is a request body aimed at tenant B, with
  "{tenant}" standing for B's slug.
- "customer": a storefront endpoint; anyone may use it at any cinema, but it only ever
  returns the caller's own customer data (never staff or other customers' data).
- "storefront": public, no login; returns a cinema's published storefront only (never
  internal ids, staff or owner data). Probed anonymously at tenant B.
- "platform": the AfriCinemas platform console (P13.1); only platform staff may call it.
  Probed as tenant A's owner (not platform staff): refused as "not_platform", always.
- "webhook": a public endpoint on a custom path (key "route:<path>"), called by a
  provider (M-Pesa's callback, P5.4); it changes nothing a caller can see and only
  acknowledges. Probed anonymously with a made-up token.
- "oauth": MCP sign-in's public endpoints on custom paths (P8.6a): client registration and
  the token endpoint. Probed anonymously; they never answer with another cinema's data.
- "mcp": the MCP server (P8.2), a public JSON-RPC endpoint on a custom path; read-only,
  it answers as the storefront does. Probed anonymously with a tool call at tenant B;
  a cinema's own connector (/mcp/c/{slug}, P8.3) is tenant A's, asked about tenant B.

isolation_tests.jac fails when the app serves an endpoint that isn't listed here, so no
new endpoint can skip the cross-tenant checks.

`audit` is the action the endpoint records in the cinema's audit log (P7.2), or "" for
one that records nothing. tests/integration/audit_meta_tests.jac calls every endpoint
and checks it records exactly that: one event of that action, or none.
"""

glob REGISTRY: dict[str, dict[str, any]] = {  # jac:ignore[W1037]
         "app_info": {"scope": "public", "audit": ""},
         # Which of the three sites an address is (P13.1b.c): names no more than it.
         "site_for_host": {
             "scope": "public",
             "audit": "",
             "probe": {"host": "nova.localhost:8000"}
         },
         "create_cinema": {"scope": "caller", "audit": "cinema.created"},
         # Confirming a staff account's email (P14.2): the caller's own, or a link's.
         "send_email_check": {
             "scope": "caller",
             "audit": "",
             "probe": {"email": "owner@example.com"}
         },
         "confirm_email": {
             "scope": "public",
             "audit": "",
             "probe": {"token": "made-up-token"}
         },
         # The caller's own name and password (P12.15).
         "my_profile": {
             "scope": "caller",
             "audit": "",
             "probe": {"sign_in": "owner@example.com"}
         },
         "save_my_name": {"scope": "caller", "audit": "", "probe": {"name": "Probe"}},
         "change_my_password": {
             "scope": "caller",
             "audit": "",
             "probe": {
                 "sign_in": "owner@example.com",
                 "current_password": "wrong-password",
                 "new_password": "Another-passw0rd"
             }
         },
         "email_status": {
             "scope": "caller",
             "audit": "",
             "probe": {"email": "owner@example.com"}
         },
         "my_cinemas": {"scope": "caller", "audit": ""},
         # The AfriCinemas platform console (P13.1): its actions go to the platform's own
         # log, never a cinema's.
         "platform_whoami": {"scope": "caller", "audit": ""},
         # A join link's page (P13.1b.a): no account yet; a token names who may join.
         "platform_join": {
             "scope": "public",
             "audit": "",
             "probe": {"token": "made-up-token", "password": "Probe-Passw0rd!"}
         },
         "platform_staff": {"scope": "platform", "audit": ""},
         # The platform's own audit log and its sign-ins (P13.3), for platform staff.
         "platform_audit_log": {
             "scope": "platform",
             "audit": "",
             "probe": {"limit": 10}
         },
         "platform_signed_in": {"scope": "platform", "audit": ""},
         # Technical support (P13.5a): a cinema's requests are its own; the inbox is
         # for platform support staff.
         "ask_for_help": {
             "scope": "tenant",
             "audit": "support.requested",
             "probe": {"tenant": "{tenant}", "category": "other", "text": "Probe"}
         },
         "support_requests": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "reply_to_support": {
             "scope": "tenant",
             "audit": "support.replied",
             "probe": {"tenant": "{tenant}", "request_id": "x", "text": "Probe"}
         },
         # Marking a conversation read (its unread count): changes nothing else.
         "support_seen": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "request_id": "x"}
         },
         "platform_support_seen": {
             "scope": "platform",
             "audit": "",
             "probe": {"request_id": "x"}
         },
         # A screenshot in a help request (P13.5b): the cinema's own, or ours to read.
         "support_image": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "request_id": "x", "index": 0}
         },
         "platform_support_image": {
             "scope": "platform",
             "audit": "",
             "probe": {"request_id": "x", "index": 0}
         },
         "platform_support_requests": {"scope": "platform", "audit": ""},
         "platform_support_request": {
             "scope": "platform",
             "audit": "",
             "probe": {"request_id": "x"}
         },
         "platform_support_reply": {
             "scope": "platform",
             "audit": "",
             "probe": {"request_id": "x", "text": "Probe"}
         },
         "platform_support_status": {
             "scope": "platform",
             "audit": "",
             "probe": {"request_id": "x", "status": "closed"}
         },
         # The platform overview (P13.4): figures across every cinema.
         "platform_overview": {"scope": "platform", "audit": ""},
         # The cinemas directory (P13.2): every cinema, for platform staff only.
         "platform_cinemas": {"scope": "platform", "audit": ""},
         # A reviewer makes a cinema live (P14.1, until 14.5's review).
         "platform_approve_cinema": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         # Reviewing a cinema's verification (P14.5): reviewers and super admins.
         "platform_reviews": {"scope": "platform", "audit": "", "probe": {}},
         "platform_review": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "platform_review_file": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "imax-rift", "item": "id_front"}
         },
         "platform_decide": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "imax-rift", "decision": "approve", "reasons": []}
         },
         "platform_cinema": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "invite_platform_member": {
             "scope": "platform",
             "audit": "",
             "probe": {"email": "probe@example.com", "role": "support"}
         },
         "set_platform_role": {
             "scope": "platform",
             "audit": "",
             "probe": {"email": "probe@example.com", "role": "support"}
         },
         "remove_platform_staff": {
             "scope": "platform",
             "audit": "",
             "probe": {"email": "probe@example.com"}
         },
         # The fee rule (P15.1): platform staff read it, super admins set it.
         "fee_rules": {"scope": "platform", "audit": ""},
         "set_fee_rule": {
             "scope": "platform",
             "audit": "",
             "probe": {
                 "online_ticket_percent": 7,
                 "online_snack_percent": 20,
                 "counter_percent": 3,
                 "applies_from": "2099-01-01"
             }
         },
         # A cinema's own fee terms (P15.2): platform staff read them, super admins set
         # them; the cinema's reports staff read the rates in force for them.
         "cinema_fee_terms": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "{tenant}"}
         },
         "set_cinema_fee_terms": {
             "scope": "platform",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "standard": True,
                 "online_ticket_percent": 0,
                 "online_snack_percent": 0,
                 "counter_percent": 0,
                 "applies_from": "2099-01-01",
                 "note": ""
             }
         },
         "my_fee_rates": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         # The cinema agreement (P15.1): any member reads its status; the owner accepts.
         "cinema_agreement_status": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "cinema_agreement_text": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "accept_cinema_agreement": {
             "scope": "tenant",
             "audit": "cinema.agreement_accepted",
             "probe": {"tenant": "{tenant}", "version": "0.1"}
         },
         # Each cinema's own M-Pesa (P15.3): settings staff read it; the owner connects,
         # tests and cancels. Never a key in any answer.
         "mpesa_settings": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "connect_mpesa": {
             "scope": "tenant",
             "audit": "mpesa.connected",
             "probe": {
                 "tenant": "{tenant}",
                 "kind": "paybill",
                 "shortcode": "174379",
                 "till_number": "",
                 "registered_name": "Probe Ltd",
                 "keys": {
                     "consumer_key": "probeprobe",
                     "consumer_secret": "probeprobe",
                     "passkey": "probeprobe"
                 },
                 "password": "probe",
                 "sign_in": "probe@example.com"
             }
         },
         "test_mpesa": {
             "scope": "tenant",
             "audit": "mpesa.test_sent",
             "probe": {"tenant": "{tenant}", "phone": "0712345678"}
         },
         "mpesa_test_status": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "cancel_mpesa_change": {
             "scope": "tenant",
             "audit": "mpesa.cancelled",
             "probe": {"tenant": "{tenant}", "sign_in": "probe@example.com"}
         },
         # AfriCinemas' M-Pesa setup video (P15.3): platform staff read it; super
         # admins set it.
         "mpesa_guide_video": {"scope": "platform", "audit": ""},
         "set_mpesa_guide_video": {
             "scope": "platform",
             "audit": "",
             "probe": {"url": "https://youtu.be/probe12345"}
         },
         # The registrations checklist (P15.0b): super admins only.
         "registrations_checklist": {"scope": "platform", "audit": ""},
         "tick_registration": {
             "scope": "platform",
             "audit": "",
             "probe": {"key": "domain", "done": True, "reference": "probe"}
         },
         # Monthly statements and invoices (P15.4): the cinema's finance readers; platform
         # staff read every cinema's, and super admins issue them.
         "billing": {"scope": "tenant", "audit": "", "probe": {"tenant": "{tenant}"}},
         "billing_pdf": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "number": "AC999999"}
         },
         "platform_billing": {"scope": "platform", "audit": ""},
         "platform_billing_pdf": {
             "scope": "platform",
             "audit": "",
             "probe": {"number": "AC999999"}
         },
         "platform_issue_statements": {"scope": "platform", "audit": ""},
         # Reconciliation and AfriCinemas' takings (P15.6).
         "reconciliation": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "resolve_exception": {
             "scope": "tenant",
             "audit": "reconcile.resolved",
             "probe": {"tenant": "{tenant}", "exception_id": "x", "note": "probe"}
         },
         "reconciliation_open": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "count_cash": {
             "scope": "tenant",
             "audit": "cash.counted",
             "probe": {"tenant": "{tenant}", "counted_cents": 0}
         },
         "count_left_cash": {
             "scope": "tenant",
             "audit": "cash.counted_for",
             "probe": {"tenant": "{tenant}", "member_id": "x", "counted_cents": 0}
         },
         "recount_cash": {
             "scope": "tenant",
             "audit": "cash.recounted",
             "probe": {"tenant": "{tenant}", "counted_cents": 0}
         },
         "cash_status": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "platform_reconciliation": {"scope": "platform", "audit": ""},
         "platform_takings": {"scope": "platform", "audit": ""},
         # Collecting what's owed (P15.5).
         "pay_invoice": {
             "scope": "tenant",
             "audit": "billing.payment_started",
             "probe": {
                 "tenant": "{tenant}",
                 "number": "AC999999",
                 "phone": "0712345678"
             }
         },
         "invoice_payment": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "reference": "BILLPROBE"}
         },
         "dispute_invoice": {
             "scope": "tenant",
             "audit": "billing.disputed",
             "probe": {
                 "tenant": "{tenant}",
                 "number": "AC999999",
                 "text": "Probe probe"
             }
         },
         "billing_notice": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "platform_decide_dispute": {
             "scope": "platform",
             "audit": "",
             "probe": {"number": "AC999999", "outcome": "stands", "note": "probe"}
         },
         "platform_resolve_payment": {
             "scope": "platform",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "reference": "BILLPROBE",
                 "action": "refund",
                 "number": "",
                 "note": "probe"
             }
         },
         "platform_suspend_cinema": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "{tenant}", "reason": "probe reason"}
         },
         "platform_reinstate_cinema": {
             "scope": "platform",
             "audit": "",
             "probe": {"slug": "{tenant}"}
         },
         # AfriCinemas' legal pages (P15.0b): public.
         "legal_document": {"scope": "public", "audit": "", "probe": {"name": "terms"}},
         "check_slug": {"scope": "caller", "audit": "", "probe": {"slug": "free-name"}},
         "my_access": {"scope": "tenant", "audit": "", "probe": {"tenant": "{tenant}"}},
         # The cinema's public information (P14.3a): its staff who change settings.
         "site_info": {"scope": "tenant", "audit": "", "probe": {"tenant": "{tenant}"}},
         "save_site_info": {
             "scope": "tenant",
             "audit": "site_info.saved",
             "probe": {"tenant": "{tenant}", "info": {"business_name": "Probe"}}
         },
         # The cinema's policies (P14.3b): its staff who change settings.
         "policies": {"scope": "tenant", "audit": "", "probe": {"tenant": "{tenant}"}},
         "save_policy": {
             "scope": "tenant",
             "audit": "policy.saved",
             "probe": {
                 "tenant": "{tenant}",
                 "kind": "terms",
                 "text": "Probe",
                 "published": False,
                 "reviewed": False
             }
         },
         # Verifying the owner and the business (P14.4): the owner alone.
         "verification": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "save_verification": {
             "scope": "tenant",
             "audit": "verification.saved",
             "probe": {"tenant": "{tenant}", "details": {"legal_name": "Probe"}}
         },
         "upload_verification_file": {
             "scope": "tenant",
             "audit": "verification.file_uploaded",
             "probe": {
                 "tenant": "{tenant}",
                 "item": "id_front",
                 "content_type": "application/pdf",
                 "data_base64": "JVBERi0="
             }
         },
         "verification_file": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "item": "id_front"}
         },
         "submit_verification": {
             "scope": "tenant",
             "audit": "verification.submitted",
             "probe": {"tenant": "{tenant}"}
         },
         # A policy as a PDF, and the public documents (P14.3d).
         "upload_policy_pdf": {
             "scope": "tenant",
             "audit": "policy.pdf_uploaded",
             "probe": {"tenant": "{tenant}", "kind": "terms", "data_base64": "JVBERi0="}
         },
         "remove_policy_pdf": {
             "scope": "tenant",
             "audit": "policy.pdf_removed",
             "probe": {"tenant": "{tenant}", "kind": "terms"}
         },
         "public_documents_admin": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "upload_public_document": {
             "scope": "tenant",
             "audit": "document.uploaded",
             "probe": {
                 "tenant": "{tenant}",
                 "title": "Probe",
                 "data_base64": "JVBERi0="
             }
         },
         "remove_public_document": {
             "scope": "tenant",
             "audit": "document.removed",
             "probe": {"tenant": "{tenant}", "document_id": "probe"}
         },
         # A pass for the cinema's own team to preview its storefront (P14.1).
         "storefront_preview": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "rename_cinema": {
             "scope": "tenant",
             "audit": "cinema.renamed",
             "probe": {"tenant": "{tenant}", "name": "Probe"}
         },
         "set_doors_open": {
             "scope": "tenant",
             "audit": "cinema.doors_changed",
             "probe": {"tenant": "{tenant}", "minutes": 30}
         },
         "box_office_rules": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "set_box_office_rules": {
             "scope": "tenant",
             "audit": "cinema.box_office_rules_changed",
             "probe": {
                 "tenant": "{tenant}",
                 "shift_hours": 8,
                 "cash_count_max_cents": 50000000
             }
         },
         "invite_staff": {
             "scope": "tenant",
             "audit": "staff.invited",
             "probe": {"tenant": "{tenant}", "role": "usher", "venue_id": ""}
         },
         "accept_invite": {
             "scope": "caller",
             "audit": "staff.joined",
             "probe": {"token": "not-a-real-token"}
         },
         "list_staff": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "start_shift": {
             "scope": "tenant",
             "audit": "shift.started",
             "probe": {"tenant": "{tenant}"}
         },
         "end_shift": {
             "scope": "tenant",
             "audit": "shift.ended",
             "probe": {"tenant": "{tenant}"}
         },
         "change_staff_roles": {
             "scope": "tenant",
             "audit": "staff.roles_changed",
             "probe": {"tenant": "{tenant}", "member_id": "x", "roles": ["owner"]}
         },
         "set_staff_status": {
             "scope": "tenant",
             "audit": "staff.status_changed",
             "probe": {"tenant": "{tenant}", "member_id": "x", "status": "disabled"}
         },
         "remove_staff": {
             "scope": "tenant",
             "audit": "staff.removed",
             "probe": {"tenant": "{tenant}", "member_id": "x"}
         },
         "create_venue": {
             "scope": "tenant",
             "audit": "venue.created",
             "probe": {"tenant": "{tenant}", "name": "Probe", "city": "", "address": ""}
         },
         "list_venues": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "update_venue": {
             "scope": "tenant",
             "audit": "venue.updated",
             "probe": {
                 "tenant": "{tenant}",
                 "venue_id": "x",
                 "name": "Probe",
                 "city": "",
                 "address": ""
             }
         },
         "delete_venue": {
             "scope": "tenant",
             "audit": "venue.deleted",
             "probe": {"tenant": "{tenant}", "venue_id": "x"}
         },
         "create_auditorium": {
             "scope": "tenant",
             "audit": "screen.created",
             "probe": {"tenant": "{tenant}", "venue_id": "x", "name": "Probe"}
         },
         "rename_auditorium": {
             "scope": "tenant",
             "audit": "screen.renamed",
             "probe": {"tenant": "{tenant}", "auditorium_id": "x", "name": "Probe"}
         },
         "delete_auditorium": {
             "scope": "tenant",
             "audit": "screen.deleted",
             "probe": {"tenant": "{tenant}", "auditorium_id": "x"}
         },
         "save_layout": {
             "scope": "tenant",
             "audit": "layout.saved",
             "probe": {
                 "tenant": "{tenant}",
                 "auditorium_id": "x",
                 "rows": 1,
                 "cols": 1,
                 "seats": []
             }
         },
         "publish_layout": {
             "scope": "tenant",
             "audit": "layout.published",
             "probe": {"tenant": "{tenant}", "auditorium_id": "x"}
         },
         "list_layouts": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "auditorium_id": "x"}
         },
         "get_layout": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "layout_id": "x"}
         },
         "create_movie": {
             "scope": "tenant",
             "audit": "movie.created",
             "probe": {
                 "tenant": "{tenant}",
                 "title": "Probe",
                 "synopsis": "",
                 "runtime_minutes": 90,
                 "age_rating": "PG",
                 "genres": [],
                 "language": ""
             }
         },
         "list_movies": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "get_movie": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "movie_id": "x"}
         },
         "update_movie": {
             "scope": "tenant",
             "audit": "movie.updated",
             "probe": {
                 "tenant": "{tenant}",
                 "movie_id": "x",
                 "title": "Probe",
                 "synopsis": "",
                 "runtime_minutes": 90,
                 "age_rating": "PG",
                 "genres": [],
                 "language": ""
             }
         },
         "delete_movie": {
             "scope": "tenant",
             "audit": "movie.deleted",
             "probe": {"tenant": "{tenant}", "movie_id": "x"}
         },
         "set_trailer": {
             "scope": "tenant",
             "audit": "movie.trailer_set",
             "probe": {"tenant": "{tenant}", "movie_id": "x", "url": ""}
         },
         "upload_poster": {
             "scope": "tenant",
             "audit": "movie.poster_uploaded",
             "probe": {
                 "tenant": "{tenant}",
                 "movie_id": "x",
                 "content_type": "image/png",
                 "data_base64": ""
             }
         },
         "get_poster": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "movie_id": "x"}
         },
         "get_backdrop": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "movie_id": "x"}
         },
         # The snack catalog (P12.1).
         "duplicate_snack_product": {
             "scope": "tenant",
             "audit": "snack_product.duplicated",
             "probe": {"tenant": "{tenant}", "product_id": "x"}
         },
         "preview_snack_import": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "csv_text": "product_name,category,sku,price\nProbe,Probe,PROBE,100\n",
                 "mapping": {},
                 "create_categories": False
             }
         },
         "import_snack_catalog": {
             "scope": "tenant",
             "audit": "snack_catalog.imported",
             "probe": {
                 "tenant": "{tenant}",
                 "csv_text": "product_name,category,sku,price\nProbe,Probe,PROBE,100\n",
                 "mapping": {},
                 "create_categories": False
             }
         },
         "export_snack_catalog": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "bulk_snack_products": {
             "scope": "tenant",
             "audit": "snack_product.bulk_changed",
             "probe": {"tenant": "{tenant}", "product_ids": [], "action": "archive"}
         },
         "bulk_snack_venues": {
             "scope": "tenant",
             "audit": "snack_product.bulk_venues_set",
             "probe": {"tenant": "{tenant}", "product_ids": [], "venue_ids": []}
         },
         "snack_stock_levels": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "venue_id": "x"}
         },
         "snack_stock_history": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "venue_id": "x",
                 "variant_id": "",
                 "limit": 10
             }
         },
         "adjust_snack_stock": {
             "scope": "tenant",
             "audit": "snack_stock.adjusted",
             "probe": {
                 "tenant": "{tenant}",
                 "product_id": "x",
                 "variant_id": "x",
                 "venue_id": "x",
                 "reason": "received",
                 "quantity": 1,
                 "note": ""
             }
         },
         "set_snack_stock_rules": {
             "scope": "tenant",
             "audit": "snack_stock.rules_set",
             "probe": {
                 "tenant": "{tenant}",
                 "product_id": "x",
                 "variant_id": "x",
                 "venue_id": "x",
                 "low_threshold": 0,
                 "at_zero": "unavailable"
             }
         },
         "list_snack_variants": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "list_snack_addon_groups": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "save_snack_addon_group": {
             "scope": "tenant",
             "audit": "snack_addons.saved",
             "probe": {
                 "tenant": "{tenant}",
                 "group_id": "x",
                 "name": "Probe",
                 "label": "Probe",
                 "min_picks": 0,
                 "max_picks": 1,
                 "repeatable": False,
                 "options": [{"name": "Probe", "price_cents": 0}]
             }
         },
         "delete_snack_addon_group": {
             "scope": "tenant",
             "audit": "snack_addons.deleted",
             "probe": {"tenant": "{tenant}", "group_id": "x"}
         },
         "set_snack_addon_availability": {
             "scope": "tenant",
             "audit": "snack_addons.availability_changed",
             "probe": {
                 "tenant": "{tenant}",
                 "group_id": "x",
                 "option_id": "x",
                 "venue_id": "x",
                 "available": True
             }
         },
         "set_snack_product_addons": {
             "scope": "tenant",
             "audit": "snack_product.addons_set",
             "probe": {"tenant": "{tenant}", "product_id": "x", "group_ids": []}
         },
         "set_snack_combo_components": {
             "scope": "tenant",
             "audit": "snack_product.components_set",
             "probe": {"tenant": "{tenant}", "product_id": "x", "components": []}
         },
         "set_snack_product_venues": {
             "scope": "tenant",
             "audit": "snack_product.venues_set",
             "probe": {"tenant": "{tenant}", "product_id": "x", "venue_ids": []}
         },
         "set_snack_variant_availability": {
             "scope": "tenant",
             "audit": "snack_variant.availability_changed",
             "probe": {
                 "tenant": "{tenant}",
                 "product_id": "x",
                 "variant_id": "x",
                 "venue_id": "x",
                 "available": True
             }
         },
         "set_snack_venue_price": {
             "scope": "tenant",
             "audit": "snack_variant.venue_price_set",
             "probe": {
                 "tenant": "{tenant}",
                 "product_id": "x",
                 "variant_id": "x",
                 "venue_id": "x",
                 "price_cents": None
             }
         },
         "list_snack_categories": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "create_snack_category": {
             "scope": "tenant",
             "audit": "snack_category.created",
             "probe": {"tenant": "{tenant}", "name": "Probe"}
         },
         "add_default_snack_categories": {
             "scope": "tenant",
             "audit": "snack_category.defaults_added",
             "probe": {"tenant": "{tenant}"}
         },
         "rename_snack_category": {
             "scope": "tenant",
             "audit": "snack_category.renamed",
             "probe": {"tenant": "{tenant}", "category_id": "x", "name": "Probe"}
         },
         "reorder_snack_categories": {
             "scope": "tenant",
             "audit": "snack_category.reordered",
             "probe": {"tenant": "{tenant}", "category_ids": []}
         },
         "set_snack_category_status": {
             "scope": "tenant",
             "audit": "snack_category.status_changed",
             "probe": {"tenant": "{tenant}", "category_id": "x", "status": "archived"}
         },
         "list_snack_products": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "search": "",
                 "category_id": "",
                 "status": ""
             }
         },
         "get_snack_product": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "product_id": "x"}
         },
         "get_snack_image": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "product_id": "x", "image_id": "x"}
         },
         "save_snack_product": {
             "scope": "tenant",
             "audit": "snack_product.saved",
             "probe": {
                 "tenant": "{tenant}",
                 "product_id": "x",
                 "name": "Probe",
                 "brand": "",
                 "description": "",
                 "tags": [],
                 "category_id": "x",
                 "kind": "single",
                 "option_names": [],
                 "variants": []
             }
         },
         "configure_3d_glasses": {
             "scope": "tenant",
             "audit": "snack_glasses.configured",
             "probe": {
                 "tenant": "{tenant}",
                 "venue_id": "x",
                 "sold": False,
                 "price_cents": 0
             }
         },
         "list_3d_glasses": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "publish_snack_product": {
             "scope": "tenant",
             "audit": "snack_product.published",
             "probe": {"tenant": "{tenant}", "product_id": "x"}
         },
         "unpublish_snack_product": {
             "scope": "tenant",
             "audit": "snack_product.unpublished",
             "probe": {"tenant": "{tenant}", "product_id": "x"}
         },
         "archive_snack_product": {
             "scope": "tenant",
             "audit": "snack_product.archived",
             "probe": {"tenant": "{tenant}", "product_id": "x"}
         },
         "restore_snack_product": {
             "scope": "tenant",
             "audit": "snack_product.restored",
             "probe": {"tenant": "{tenant}", "product_id": "x"}
         },
         "delete_snack_product": {
             "scope": "tenant",
             "audit": "snack_product.deleted",
             "probe": {"tenant": "{tenant}", "product_id": "x"}
         },
         "upload_snack_image": {
             "scope": "tenant",
             "audit": "snack_product.image_added",
             "probe": {
                 "tenant": "{tenant}",
                 "product_id": "x",
                 "content_type": "image/png",
                 "data_base64": ""
             }
         },
         "remove_snack_image": {
             "scope": "tenant",
             "audit": "snack_product.image_removed",
             "probe": {"tenant": "{tenant}", "product_id": "x", "image_id": "x"}
         },
         "create_screening": {
             "scope": "tenant",
             "audit": "showtime.created",
             "probe": {
                 "tenant": "{tenant}",
                 "auditorium_id": "x",
                 "movie_id": "x",
                 "starts_at": "2030-01-01T18:00:00+00:00"
             }
         },
         "set_screening_format": {
             "scope": "tenant",
             "audit": "showtime.format_changed",
             "probe": {"tenant": "{tenant}", "screening_id": "x", "format": "3D"}
         },
         "list_screenings": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "auditorium_id": "x"}
         },
         "get_screening": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "screening_id": "x"}
         },
         "reschedule_screening": {
             "scope": "tenant",
             "audit": "showtime.rescheduled",
             "probe": {
                 "tenant": "{tenant}",
                 "screening_id": "x",
                 "starts_at": "2030-01-01T18:00:00+00:00"
             }
         },
         "schedule_screening": {
             "scope": "tenant",
             "audit": "showtime.scheduled",
             "probe": {"tenant": "{tenant}", "screening_id": "x"}
         },
         "cancel_screening": {
             "scope": "tenant",
             "audit": "showtime.cancelled",
             "probe": {"tenant": "{tenant}", "screening_id": "x"}
         },
         "publish_screening": {
             "scope": "tenant",
             "audit": "showtime.published",
             "probe": {"tenant": "{tenant}", "screening_id": "x"}
         },
         "unpublish_screening": {
             "scope": "tenant",
             "audit": "showtime.unpublished",
             "probe": {"tenant": "{tenant}", "screening_id": "x"}
         },
         "list_seat_slots": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "screening_id": "x"}
         },
         "door_showtimes": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "counter_showtimes": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         # Snacks only, at the box office (P12.10): selling at the venue.
         "counter_snack_venues": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "counter_price_snacks": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "venue_id": "x", "lines": []}
         },
         "counter_snack_menu": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "venue_id": "x"}
         },
         "place_snack_order": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "venue_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "idempotency_key": "probe-idempotency-key-xxxxxxxx",
                 "snacks": []
             }
         },
         "sell_snacks_for_cash": {
             "scope": "tenant",
             "audit": "sale.snacks_cash",
             "probe": {
                 "tenant": "{tenant}",
                 "venue_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "sell_snacks_with_mpesa": {
             "scope": "tenant",
             "audit": "sale.snacks_mpesa",
             "probe": {
                 "tenant": "{tenant}",
                 "venue_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "phone": "0712345678",
                 "email": "",
                 "idempotency_key": "probe-idempotency-key-xxxxxxxx"
             }
         },
         "counter_snack_payment": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "venue_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "sell_for_cash": {
             "scope": "tenant",
             "audit": "sale.cash",
             "probe": {
                 "tenant": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "email": ""
             }
         },
         "sell_with_mpesa": {
             "scope": "tenant",
             "audit": "sale.mpesa_started",
             "probe": {
                 "tenant": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "phone": "0712345678",
                 "email": ""
             }
         },
         "showtime_art": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "screening_id": "x", "kind": "poster"}
         },
         "staff_home": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "setup_steps": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "audit_log": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "before": "", "limit": 10, "action": ""}
         },
         "sales_report": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "date_from": "2026-10-01",
                 "date_to": "2026-10-07",
                 "venue_id": ""
             }
         },
         "redeem_ticket": {
             "scope": "tenant",
             "audit": "ticket.scanned",
             "probe": {"tenant": "{tenant}", "screening_id": "x", "code": "x"}
         },
         # Collecting snacks at the snack counter (P12.9).
         "snack_pickup": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "code": "x"}
         },
         "hand_over_snacks": {
             "scope": "tenant",
             "audit": "snacks.handed_over",
             "probe": {"tenant": "{tenant}", "code": "x"}
         },
         "public_screenings": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "public_home": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "public_movie": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "movie_key": "x"}
         },
         "public_screening": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "screening_id": "x"}
         },
         "public_poster": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "movie_key": "x"}
         },
         # The snack menu (P12.6).
         "public_snacks": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "screening_id": "x"}
         },
         "price_snacks": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "screening_id": "x", "lines": []}
         },
         "public_snack_image": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "product_id": "x", "image_id": "x"}
         },
         "get_price_list": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "save_price_list": {
             "scope": "tenant",
             "audit": "prices.saved",
             "probe": {
                 "tenant": "{tenant}",
                 "timezone": "Africa/Nairobi",
                 "ticket_types": [{"code": "ADULT", "name": "Adult"}],
                 "prices": [],
                 "surcharges": [],
                 "service_fee_cents": 0
             }
         },
         "quote_tickets": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "screening_id": "x",
                 "items": [{"seat_label": "A1", "ticket_type": "ADULT"}]
             }
         },
         "get_branding": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "save_theme": {
             "scope": "tenant",
             "audit": "theme.saved",
             "probe": {"tenant": "{tenant}", "theme": {"name": "Probe"}}
         },
         "draw_brand_kit": {
             "scope": "tenant",
             "audit": "theme.kit_drawn",
             "probe": {"tenant": "{tenant}"}
         },
         "design_storefront": {
             "scope": "tenant",
             "audit": "theme.designed",
             "probe": {"tenant": "{tenant}"}
         },
         "set_brand_look": {
             "scope": "tenant",
             "audit": "theme.kit_styled",
             "probe": {
                 "tenant": "{tenant}",
                 "look": {
                     "card": "rounded",
                     "frame": "none",
                     "divider": "line",
                     "heading": "natural"
                 }
             }
         },
         "remove_brand_kit": {
             "scope": "tenant",
             "audit": "theme.kit_removed",
             "probe": {"tenant": "{tenant}"}
         },
         "suggest_themes": {
             "scope": "tenant",
             "audit": "theme.suggested",
             "probe": {"tenant": "{tenant}"}
         },
         "upload_logo": {
             "scope": "tenant",
             "audit": "theme.logo_uploaded",
             "probe": {
                 "tenant": "{tenant}",
                 "content_type": "image/png",
                 "data_base64": ""
             }
         },
         "remove_logo": {
             "scope": "tenant",
             "audit": "theme.logo_removed",
             "probe": {"tenant": "{tenant}"}
         },
         "publish_theme": {
             "scope": "tenant",
             "audit": "theme.published",
             "probe": {"tenant": "{tenant}"}
         },
         "rollback_theme": {
             "scope": "tenant",
             "audit": "theme.rolled_back",
             "probe": {"tenant": "{tenant}", "version": 1}
         },
         "public_branding": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "get_home_page": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "save_home_page": {
             "scope": "tenant",
             "audit": "home_page.saved",
             "probe": {
                 "tenant": "{tenant}",
                 "page": {"template": "compact", "sections": []}
             }
         },
         "publish_home_page": {
             "scope": "tenant",
             "audit": "home_page.published",
             "probe": {"tenant": "{tenant}"}
         },
         "preview_home_page": {
             "scope": "tenant",
             "audit": "",
             "probe": {
                 "tenant": "{tenant}",
                 "page": {"template": "compact", "sections": []}
             }
         },
         "upload_home_photo": {
             "scope": "tenant",
             "audit": "home_page.photo_uploaded",
             "probe": {
                 "tenant": "{tenant}",
                 "content_type": "image/png",
                 "data_base64": ""
             }
         },
         "get_home_photo": {
             "scope": "tenant",
             "audit": "",
             "probe": {"tenant": "{tenant}", "photo": "x"}
         },
         "remove_home_photo": {
             "scope": "tenant",
             "audit": "home_page.photo_removed",
             "probe": {"tenant": "{tenant}", "photo": "x"}
         },
         "upload_backdrop": {
             "scope": "tenant",
             "audit": "movie.backdrop_uploaded",
             "probe": {
                 "tenant": "{tenant}",
                 "movie_id": "x",
                 "content_type": "image/png",
                 "data_base64": ""
             }
         },
         "remove_backdrop": {
             "scope": "tenant",
             "audit": "movie.backdrop_removed",
             "probe": {"tenant": "{tenant}", "movie_id": "x"}
         },
         "customer_sign_up": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "email": "probe@example.com",
                 "password": "probe-password-1",
                 "name": "Probe",
                 "adult": "yes"
             }
         },
         "my_storefront_account": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "cinema_chat": {
             "scope": "customer",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "message": "",
                 "history": [],
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "agent_chat": {
             "scope": "customer",
             "audit": "",
             "probe": {
                 "message": "",
                 "history": [],
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "public_cinemas": {"scope": "public", "audit": "", "probe": {"city": ""}},
         # A cinema's public information (P14.3a): its published storefront's, no one's
         # details.
         "public_site_info": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}"}
         },
         # A cinema's published policy (P14.3b): its public storefront's.
         "public_policy": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "kind": "terms"}
         },
         # The Verified badge's check (P14.5): the same answer for anything not verified.
         "verified_cinema": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}"}
         },
         "public_policies": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}"}
         },
         "public_policy_pdf": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "kind": "terms"}
         },
         "public_document": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "document_id": "probe"}
         },
         "public_venues": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "hold_seats": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "labels": ["A1"]
             }
         },
         "my_hold": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "extend_hold": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "release_hold": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "place_order": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "idempotency_key": "probe-key-xxxxxxxxxxxxxxxx",
                 "items": [{"seat_label": "A1", "ticket_type": "ADULT"}]
             }
         },
         "quote_hold": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "items": [{"seat_label": "A1", "ticket_type": "ADULT"}]
             }
         },
         "public_ticket_types": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         # Back from paying to change the order: the holder's own unpaid order.
         "change_order": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "my_order": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "start_payment": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef",
                 "phone": "0712345678",
                 "email": "probe@example.com",
                 "idempotency_key": "probe-key-xxxxxxxxxxxxxxxx",
                 "adult": "yes"
             }
         },
         "more_snacks": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "token": "probetokenxxxxxxxxxxxxxxxx"}
         },
         "counter_more_snacks": {
             "scope": "tenant",
             "audit": "sale.extra_snacks",
             "probe": {"tenant": "{tenant}", "reference": "UNKNOWN", "action": "place"}
         },
         "tickets_by_link": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "token": "probetokenxxxxxxxxxxxxxxxx"}
         },
         "resend_tickets": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "token": "probetokenxxxxxxxxxxxxxxxx",
                 "email": ""
             }
         },
         "end_my_order": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "my_payment": {
             "scope": "storefront",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "screening_id": "x",
                 "holder": "probe-holder-0123456789abcdef"
             }
         },
         "route:/mcp": {
             "scope": "mcp",
             "audit": "",
             "probe": {
                 "jsonrpc": "2.0",
                 "id": 1,
                 "method": "tools/call",
                 "params": {
                     "name": "show_movie",
                     "arguments": {"cinema": "{tenant}", "movie": "x"}
                 }
             }
         },
         "route:/mcp/c/{slug}": {
             "scope": "mcp",
             "audit": "",
             "probe": {
                 "jsonrpc": "2.0",
                 "id": 1,
                 "method": "tools/call",
                 "params": {"name": "whats_on", "arguments": {"cinema": "{tenant}"}}
             }
         },
         "oauth_consent_info": {
             "scope": "caller",
             "audit": "",
             "probe": {
                 "client_id": "probe",
                 "redirect_uri": "https://claude.ai/cb",
                 "resource": ""
             }
         },
         "oauth_approve": {
             "scope": "caller",
             "audit": "",
             "probe": {
                 "client_id": "probe",
                 "redirect_uri": "https://claude.ai/cb",
                 "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
                 "code_challenge_method": "S256",
                 "resource": "",
                 "scope": "",
                 "state": ""
             }
         },
         "oauth_deny": {
             "scope": "caller",
             "audit": "",
             "probe": {
                 "client_id": "probe",
                 "redirect_uri": "https://claude.ai/cb",
                 "resource": "",
                 "state": ""
             }
         },
         "route:/oauth/register": {
             "scope": "oauth",
             "audit": "",
             "probe": {
                 "client_name": "Probe",
                 "redirect_uris": ["https://claude.ai/cb"]
             }
         },
         "route:/oauth/token": {
             "scope": "oauth",
             "audit": "",
             "probe": {
                 "grant_type": "refresh_token",
                 "refresh_token": "x",
                 "client_id": "y"
             }
         },
         "route:/hooks/mpesa/{token}": {
             "scope": "webhook",
             "audit": "",
             "probe": {"Body": {"stkCallback": {"ResultCode": 0}}}
         },
         "route:/hooks/mpesa-bill/{token}": {
             "scope": "webhook",
             "audit": "",
             "probe": {"Body": {"stkCallback": {"ResultCode": 0}}}
         },
         "public_seat_availability": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "screening_id": "x"}
         },
         "public_backdrop": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "movie_key": "x"}
         },
         "public_home_photo": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}", "photo": "x"}
         },
         "rollback_home_page": {
             "scope": "tenant",
             "audit": "home_page.rolled_back",
             "probe": {"tenant": "{tenant}", "version": 1}
         },
         "join_as_customer": {
             "scope": "customer",
             "audit": "",
             "probe": {"tenant": "{tenant}", "display_name": "Probe"}
         },
         "my_customer_profile": {
             "scope": "customer",
             "audit": "",
             "probe": {"tenant": "{tenant}"}
         },
         "save_booking": {
             "scope": "customer",
             "audit": "",
             "probe": {
                 "slug": "{tenant}",
                 "token": "probetokenxxxxxxxxxxxxxxxx",
                 "display_name": "Probe"
             }
         },
         "my_tickets": {
             "scope": "customer",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         # A customer's own consent to a cinema's offers (P14.3c).
         "my_offers": {
             "scope": "customer",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "set_my_offers": {
             "scope": "customer",
             "audit": "",
             "probe": {"slug": "imax-rift", "subscribed": False, "source": ""}
         },
         # Connected apps (P8.6d): the caller's own connections at a cinema.
         "my_connected_apps": {
             "scope": "customer",
             "audit": "",
             "probe": {"slug": "imax-rift"}
         },
         "disconnect_app": {
             "scope": "customer",
             "audit": "",
             "probe": {"slug": "{tenant}", "app_id": "ac-unknown"}
         }
     };
