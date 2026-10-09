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
- "webhook": a public endpoint on a custom path (key "route:<path>"), called by a
  provider (M-Pesa's callback, P5.4); it changes nothing a caller can see and only
  acknowledges. Probed anonymously with a made-up token.

isolation_tests.jac fails when the app serves an endpoint that isn't listed here, so no
new endpoint can skip the cross-tenant checks.

`audit` is the action the endpoint records in the cinema's audit log (P7.2), or "" for
one that records nothing. tests/integration/audit_meta_tests.jac calls every endpoint
and checks it records exactly that: one event of that action, or none.
"""

glob REGISTRY: dict[str, dict[str, any]] = {  # jac:ignore[W1037]
         "app_info": {"scope": "public", "audit": ""},
         "create_cinema": {"scope": "caller", "audit": "cinema.created"},
         "my_cinemas": {"scope": "caller", "audit": ""},
         "check_slug": {"scope": "caller", "audit": "", "probe": {"slug": "free-name"}},
         "my_access": {"scope": "tenant", "audit": "", "probe": {"tenant": "{tenant}"}},
         "rename_cinema": {
             "scope": "tenant",
             "audit": "cinema.renamed",
             "probe": {"tenant": "{tenant}", "name": "Probe"}
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
         "public_screenings": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}"}
         },
         "public_home": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}"}
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
             "probe": {"slug": "{tenant}"}
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
         "public_venues": {
             "scope": "storefront",
             "audit": "",
             "probe": {"slug": "{tenant}"}
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
             "probe": {"slug": "{tenant}"}
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
                 "idempotency_key": "probe-key-xxxxxxxxxxxxxxxx"
             }
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
         "route:/hooks/mpesa/{token}": {
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
         "my_tickets": {"scope": "customer", "audit": "", "probe": {"slug": "{tenant}"}}
     };
