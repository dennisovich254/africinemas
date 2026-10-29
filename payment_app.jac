"""Test-only app entry for starting payments (P5.3). Never imported by main.jac.

The production endpoints a priced showtime, a hold, an order and a payment need, plus
probes into the simulated M-Pesa (how many prompts a payment caused, a scripted outcome
per phone number) and the payments stored for a showtime. Run with
AFRICINEMAS_PAYMENTS=simulator.
"""

import from core.booking.more_snacks_api { more_snacks, counter_more_snacks }  # jac:ignore[W2037]

import json;

import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.storefront_accounts { customer_sign_up, my_storefront_account }
import from core.oauth.connections {
    my_connected_apps,  # jac:ignore[W2037]
    disconnect_app  # jac:ignore[W2037]
}
import from core.tenancy.customer_api { join_as_customer }  # jac:ignore[W2037]
import from core.tenancy.tenant_api {
    start_shift,
    end_shift,
    my_access,
    storefront_preview,
    box_office_rules,
    set_box_office_rules
}  # jac:ignore[W2037]
import from core.tenancy.staff_api {
    invite_staff,  # jac:ignore[W2037]
    accept_invite,  # jac:ignore[W2037]
    change_staff_roles  # jac:ignore[W2037]
}
import from core.audit.audit_api { audit_log }  # jac:ignore[W2037]
import from core.reporting.staff_home { staff_home, showtime_art }  # jac:ignore[W2037]
import from core.agent.agent_api { agent_chat, cinema_chat }  # jac:ignore[W2037]
import core.agent.agent as agent_module;
import from core.theming.branding_api {
    get_branding,  # jac:ignore[W2037]
    upload_logo,  # jac:ignore[W2037]
    suggest_themes,  # jac:ignore[W2037]
    draw_brand_kit,  # jac:ignore[W2037]
    design_storefront,  # jac:ignore[W2037]
    set_brand_look,  # jac:ignore[W2037]
    remove_brand_kit,  # jac:ignore[W2037]
    publish_theme,  # jac:ignore[W2037]
    public_branding
}
import core.theming.suggest as suggest_module;
import core.theming.brandkit as brandkit_module;
import core.theming.pagecode as pagecode_module;
import core.theming.pagereview as pagereview_module;
import from core.ai.claude { ClaudeFailed }
import from core.agent.tools { HOLDER, tool_named }
import from jaclang.byllm.lib { MockLLM, MockToolCall }
import from core.audit.log { Opened, collection_of, _close }
import from core.tenancy.registry { lookup_slug }
import from core.booking.redeem_api {
    redeem_ticket,  # jac:ignore[W2037]
    door_showtimes  # jac:ignore[W2037]
}
import from core.booking.ticket_delivery {
    tickets_by_link,  # jac:ignore[W2037]
    resend_tickets,  # jac:ignore[W2037]
    send_due
}
import from core.notify.mailer { OUTBOX }
import from core.booking.counter_api {
    counter_showtimes,  # jac:ignore[W2037]
    sell_for_cash,  # jac:ignore[W2037]
    sell_with_mpesa  # jac:ignore[W2037]
}
import from core.reporting.report_api { sales_report }  # jac:ignore[W2037]
import from core.booking.customer_tickets {
    save_booking,  # jac:ignore[W2037]
    my_tickets  # jac:ignore[W2037]
}
import from core.catalog.venue_api { create_venue, create_auditorium }  # jac:ignore[W2037]
import from core.snacks.category_api {
    list_snack_categories,  # jac:ignore[W2037]
    create_snack_category,  # jac:ignore[W2037]
    add_default_snack_categories,  # jac:ignore[W2037]
    rename_snack_category,  # jac:ignore[W2037]
    reorder_snack_categories,  # jac:ignore[W2037]
    set_snack_category_status  # jac:ignore[W2037]
}
import from core.snacks.venue_api {
    set_snack_product_venues,  # jac:ignore[W2037]
    set_snack_variant_availability,  # jac:ignore[W2037]
    set_snack_venue_price  # jac:ignore[W2037]
}
import from core.snacks.extras_api {
    list_snack_variants,  # jac:ignore[W2037]
    list_snack_addon_groups,  # jac:ignore[W2037]
    save_snack_addon_group,  # jac:ignore[W2037]
    delete_snack_addon_group,  # jac:ignore[W2037]
    set_snack_addon_availability,  # jac:ignore[W2037]
    set_snack_product_addons,  # jac:ignore[W2037]
    set_snack_combo_components  # jac:ignore[W2037]
}
import from core.snacks.inventory_api {
    snack_stock_levels,  # jac:ignore[W2037]
    snack_stock_history,  # jac:ignore[W2037]
    adjust_snack_stock,  # jac:ignore[W2037]
    set_snack_stock_rules  # jac:ignore[W2037]
}
import from core.snacks.tools_api {
    duplicate_snack_product,  # jac:ignore[W2037]
    preview_snack_import,  # jac:ignore[W2037]
    import_snack_catalog,  # jac:ignore[W2037]
    export_snack_catalog,  # jac:ignore[W2037]
    bulk_snack_products,  # jac:ignore[W2037]
    bulk_snack_venues  # jac:ignore[W2037]
}
import from core.snacks.product_api {
    list_snack_products,  # jac:ignore[W2037]
    get_snack_product,  # jac:ignore[W2037]
    get_snack_image,  # jac:ignore[W2037]
    save_snack_product,  # jac:ignore[W2037]
    publish_snack_product,  # jac:ignore[W2037]
    unpublish_snack_product,  # jac:ignore[W2037]
    archive_snack_product,  # jac:ignore[W2037]
    restore_snack_product,  # jac:ignore[W2037]
    delete_snack_product,  # jac:ignore[W2037]
    upload_snack_image,  # jac:ignore[W2037]
    remove_snack_image  # jac:ignore[W2037]
}
import from core.snacks.menu_api { public_snacks, price_snacks, public_snack_image }
import from core.snacks.glasses_api { configure_3d_glasses, list_3d_glasses }
import from core.snacks.pickup_api { snack_pickup, hand_over_snacks }  # jac:ignore[W2037]
# The platform's own audit log, and its sign-ins (P13.3).
import from core.platform.audit_api {
    platform_audit_log,  # jac:ignore[W2037]
    platform_signed_in  # jac:ignore[W2037]
}
# Technical support for cinemas (P13.5a): their requests, and our inbox.
import from core.support.requests {
    ask_for_help,  # jac:ignore[W2037]
    support_requests,  # jac:ignore[W2037]
    reply_to_support,  # jac:ignore[W2037]
    support_seen,  # jac:ignore[W2037]
    support_image,  # jac:ignore[W2037]
    platform_support_image,  # jac:ignore[W2037]
    platform_support_seen,  # jac:ignore[W2037]
    platform_support_requests,  # jac:ignore[W2037]
    platform_support_request,  # jac:ignore[W2037]
    platform_support_reply,  # jac:ignore[W2037]
    platform_support_status  # jac:ignore[W2037]
}
# Emailing a cinema's owners when we reply (P13.5b), and a test-only way to run it.
import from core.support.mail { send_support_due }
import from core.platform.review_api { send_decisions_due }
import from core.tenancy.retention { retention_due }
import from core.catalog.models { Venue }
import from core.clock { now as clock_now }
import from core.tenancy.state { TenantState }
import from core.tenancy.principal { flush_now }

def:pub t_retention(days_ahead: str) -> dict[str, int] {
    # Runs the retention job as of `days_ahead` days from now (P14.5b).
    return retention_due(clock_now() + timedelta(days=int(days_ahead)));
}

def:pub t_close_cinema(slug: str) -> str {
    # The cinema starts closing (no endpoint does this yet), as of now (P14.5b).
    cinema = tenant_by_id(str(lookup_slug(slug)));
    assert cinema is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        cinema.move_to(TenantState.CLOSING);
        flush_now();
    } finally {
        restore(me);
    }
    return cinema.closed_at;
}

def:pub t_send_decision_mail -> int {
    # Sends the queued review decisions now (P14.5).
    return send_decisions_due();
}

def:pub t_send_support_mail -> int {
    return send_support_due();
}

# Confirming a staff account's email (P14.2), and a test-only way to send the links.
import from core.accounts.email_verification {
    send_email_check,  # jac:ignore[W2037]
    confirm_email,
    email_status,  # jac:ignore[W2037]
    send_checks_due
}

def:pub t_send_email_checks -> int {
    return send_checks_due();
}

# A cinema's public information, shown on every storefront page (P14.3a).
import from core.catalog.site_info {
    site_info,  # jac:ignore[W2037]
    save_site_info,  # jac:ignore[W2037]
    public_site_info
}
# A cinema's policies, linked from every storefront footer (P14.3b).
import from core.catalog.policies {
    policies,  # jac:ignore[W2037]
    save_policy,  # jac:ignore[W2037]
    public_policy,
    public_policies,
    upload_policy_pdf,  # jac:ignore[W2037]
    remove_policy_pdf,  # jac:ignore[W2037]
    public_policy_pdf
}
# Reviewing cinemas' verification, in the platform console (P14.5).
import from core.platform.review_api {
    platform_reviews,  # jac:ignore[W2037]
    platform_review,  # jac:ignore[W2037]
    platform_review_file,  # jac:ignore[W2037]
    platform_decide,  # jac:ignore[W2037]
    send_decision_mail  # jac:ignore[W2037]
}
# Snacks only, at the box office (P12.10).
import from core.booking.snack_sale {
    counter_snack_venues,  # jac:ignore[W2037]
    counter_price_snacks,  # jac:ignore[W2037]
    counter_snack_menu,  # jac:ignore[W2037]
    place_snack_order,  # jac:ignore[W2037]
    sell_snacks_for_cash,  # jac:ignore[W2037]
    sell_snacks_with_mpesa,  # jac:ignore[W2037]
    counter_snack_payment  # jac:ignore[W2037]
}
# The signed-in person's own name and password (P12.15).
import from core.accounts.profile {
    my_profile,  # jac:ignore[W2037]
    save_my_name,  # jac:ignore[W2037]
    change_my_password  # jac:ignore[W2037]
}
# AfriCinemas' legal pages and the registrations checklist (P15.0b).
import from core.legal.legal_api { legal_document }
import from core.legal.fee_rule {
    fee_rules,  # jac:ignore[W2037]
    set_fee_rule,  # jac:ignore[W2037]
    cinema_fee_terms,  # jac:ignore[W2037]
    set_cinema_fee_terms,  # jac:ignore[W2037]
    my_fee_rates  # jac:ignore[W2037]
}
import from core.legal.agreement_api {
    cinema_agreement_status,  # jac:ignore[W2037]
    cinema_agreement_text,  # jac:ignore[W2037]
    accept_cinema_agreement  # jac:ignore[W2037]
}
# AfriCinemas' M-Pesa setup video, set in the console (P15.3).
import from core.payments.setup_help {
    mpesa_guide_video,  # jac:ignore[W2037]
    set_mpesa_guide_video  # jac:ignore[W2037]
}
# Each cinema's own M-Pesa (P15.3): Settings -> Payments, and the change emails' job.
import from core.payments.mpesa_api {
    mpesa_settings,  # jac:ignore[W2037]
    connect_mpesa,  # jac:ignore[W2037]
    test_mpesa,  # jac:ignore[W2037]
    mpesa_test_status,  # jac:ignore[W2037]
    cancel_mpesa_change,  # jac:ignore[W2037]
    send_mpesa_mail,  # jac:ignore[W2037]
    send_mail_due
}
import from core.legal.registrations {
    registrations_checklist,  # jac:ignore[W2037]
    tick_registration  # jac:ignore[W2037]
}
# The data protection registers: requests and breaches (P15.0).
import from core.legal.dp_registers {
    dp_registers,  # jac:ignore[W2037]
    log_data_request,  # jac:ignore[W2037]
    data_request_step,  # jac:ignore[W2037]
    log_breach,  # jac:ignore[W2037]
    assess_breach,  # jac:ignore[W2037]
    breach_step  # jac:ignore[W2037]
}
# Deleting personal files once they're no longer needed (P14.5b).
import from core.tenancy.retention { delete_due_files }  # jac:ignore[W2037]
# Verifying the owner and the business before going public (P14.4).
import from core.tenancy.verification {
    verification,  # jac:ignore[W2037]
    save_verification,  # jac:ignore[W2037]
    upload_verification_file,  # jac:ignore[W2037]
    verification_file,  # jac:ignore[W2037]
    submit_verification,  # jac:ignore[W2037]
    verified_cinema
}
# A cinema's public documents, linked from every storefront footer (P14.3d).
import from core.catalog.documents {
    public_documents_admin,  # jac:ignore[W2037]
    upload_public_document,  # jac:ignore[W2037]
    remove_public_document,  # jac:ignore[W2037]
    public_document
}
# A customer's consent to a cinema's offers (P14.3c).
import from core.notify.offer_consent { consent_of }
import from core.accounts.customer_data { delete_due }
import from core.tenancy.verification_notice { send_notices_due }
import from core.tenancy.verification { record_of as verification_record }
import from core.catalog.poster { read_media as read_stored_media }
import from core.notify.offer_consent {
    my_offers,  # jac:ignore[W2037]
    set_my_offers  # jac:ignore[W2037]
}
# A customer's own data: download it, or delete the account (P15.0).
import from core.accounts.customer_data {
    my_data,  # jac:ignore[W2037]
    request_account_deletion,  # jac:ignore[W2037]
    cancel_account_deletion  # jac:ignore[W2037]
}
# The platform overview (P13.4).
import from core.platform.overview_api { platform_overview }  # jac:ignore[W2037]
# The platform's cinemas directory (P13.2).
import from core.platform.cinemas_api {
    platform_cinemas,  # jac:ignore[W2037]
    platform_cinema,  # jac:ignore[W2037]
    platform_approve_cinema  # jac:ignore[W2037]
}
# Which of the three sites an address is (P13.1b.c).
import from core.site { site_for_host }
# Monthly statements and invoices (P15.4).
import from core.billing.billing_api {
    billing,  # jac:ignore[W2037]
    billing_pdf,  # jac:ignore[W2037]
    platform_billing,  # jac:ignore[W2037]
    platform_billing_pdf,  # jac:ignore[W2037]
    pay_invoice,  # jac:ignore[W2037]
    invoice_payment,  # jac:ignore[W2037]
    dispute_invoice,  # jac:ignore[W2037]
    billing_notice,  # jac:ignore[W2037]
    platform_decide_dispute,  # jac:ignore[W2037]
    platform_resolve_payment,  # jac:ignore[W2037]
    platform_suspend_cinema,  # jac:ignore[W2037]
    platform_reinstate_cinema,  # jac:ignore[W2037]
    platform_issue_statements  # jac:ignore[W2037]
}
# Reconciliation and AfriCinemas' takings (P15.6).
import from core.payments.reconcile_api {
    reconciliation,  # jac:ignore[W2037]
    resolve_exception,  # jac:ignore[W2037]
    reconciliation_open,  # jac:ignore[W2037]
    count_cash,  # jac:ignore[W2037]
    recount_cash,  # jac:ignore[W2037]
    count_left_cash,  # jac:ignore[W2037]
    cash_status,  # jac:ignore[W2037]
    platform_reconciliation,  # jac:ignore[W2037]
    platform_takings,  # jac:ignore[W2037]
    reconcile_payments  # jac:ignore[W2037]
}
# Paying invoices (P15.5): M-Pesa's callback and the job that settles them.
import from core.billing.collect {
    mpesa_bill_callback,  # jac:ignore[W2037]
    settle_bill_payments  # jac:ignore[W2037]
}
import from core.billing.statements { issue_due }
import from core.billing.collect { settle_due, remind_due }
import from core.tenancy.membership { records_of }
import from core.payments.reconcile { check_all }
import from core.payments.reconcile_api { check_all_counted }
import from core.platform.cinemas_api { all_cinemas }
import from core.platform.staff_api {
    platform_whoami,  # jac:ignore[W2037]
    platform_join,
    platform_staff,  # jac:ignore[W2037]
    invite_platform_member,  # jac:ignore[W2037]
    set_platform_role,  # jac:ignore[W2037]
    remove_platform_staff  # jac:ignore[W2037]
}
import from core.catalog.layout_api { save_layout, publish_layout }  # jac:ignore[W2037]
import from core.catalog.movie_api {
    create_movie,
    list_movies,
    update_movie,
    upload_poster,
    set_trailer
}  # jac:ignore[W2037]
import from core.mcp.server { mcp, cinema_mcp }  # jac:ignore[W2037]
import from core.oauth.provider {
    oauth_server_metadata,
    oauth_resource_metadata_cinema,
    oauth_register,
    oauth_consent_info,  # jac:ignore[W2037]
    oauth_approve,  # jac:ignore[W2037]
    oauth_deny,  # jac:ignore[W2037]
    oauth_token
}  # jac:ignore[W2037]
import from core.catalog.screening_api {
    create_screening,  # jac:ignore[W2037]
    get_screening,  # jac:ignore[W2037]
    set_screening_format,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    publish_screening  # jac:ignore[W2037]
}
import from core.catalog.pricing_api { save_price_list }  # jac:ignore[W2037]
import from core.catalog.storefront_api {
    public_seat_availability,
    public_home,
    public_home_photo,
    public_backdrop,
    public_venues,
    public_cinemas,
    public_movie,
    public_screening
}  # jac:ignore[W2037]
import from core.booking.hold_api { hold_seats, extend_hold, my_hold, release_hold }  # jac:ignore[W2037]
import from core.booking.order_api {
    place_order,
    my_order,
    public_ticket_types,
    quote_hold
}  # jac:ignore[W2037]
import from core.payments.payment_api { start_payment }  # jac:ignore[W2037]
import from core.payments.settlement {
    my_payment,  # jac:ignore[W2037]
    mpesa_callback,  # jac:ignore[W2037]
    process_inbox,  # jac:ignore[W2037]
    tenant_by_id
}
import from core.payments.resolver { resolve, end_my_order }  # jac:ignore[W2037]
# Back from paying to change the seats, tickets or snacks (owner, 2026-10-27).
import from core.booking.change_order { change_order }
import from core.payments.ledger { LedgerEntry }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id, act_as, restore, commit_now }
import from core.tenancy.models { Tenant }
import from core.catalog.venues { find_screening, slots_of }
import from core.catalog.models { Screening }
import from core.booking.models { Order, Ticket }
import from core.payments.models { PaymentIntent, RefundTask }
import from core.payments.choice { payment_provider }
import from core.payments.simulator { SimulatedProvider }
import from core.claims { claim, holder }
import from core.booking.ticket_codes { REFS, reserve_reference }
import from datetime { datetime, timedelta }
import from core.clock { freeze, reset, advance }

def _simulator -> SimulatedProvider {
    made = payment_provider();
    assert isinstance(made, SimulatedProvider);
    return made as SimulatedProvider;
}

def:pub pay_push_count(reference: str) -> int {
    return _simulator().push_count(reference);
}

def:pub pay_script(phone: str, outcome: str) -> bool {
    _simulator().outcomes[phone] = outcome;
    return True;
}

def:pub pay_paid_to(reference: str) -> str {
    # The paybill or till a push went to (P15.3): "" for the platform's test one.
    return _simulator().paid_to(reference);
}

def:pub t_send_mpesa_mail -> int {
    # Sends the queued M-Pesa connection emails now (P15.3).
    return send_mail_due();
}

def:pub t_clock_ahead(hours: int) -> bool {
    # Moves the clock on (AFRICINEMAS_CLOCK_CONTROL=1 only): a change's 24 hours (P15.3).
    advance(hours * 3600);
    return True;
}

def:pub t_clock_at(at: str) -> bool {
    # Stops the clock at the ISO time `at` (AFRICINEMAS_CLOCK_CONTROL=1 only, P15.5).
    freeze(datetime.fromisoformat(at));
    return True;
}

def:pub t_clock_reset -> bool {
    reset();
    return True;
}

def:pub t_owner_email(slug: str, email: str) -> bool {
    # Gives the cinema's owners `email`, where billing emails go (P15.5).
    cinema = tenant_by_id(str(lookup_slug(slug)));
    assert cinema is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for m in records_of(cinema) {
            if "owner" in m.roles {
                m.email = email;
            }
        }
        commit_now();
    } finally {
        restore(me);
    }
    return True;
}

def:pub t_reconcile -> int {
    # The daily M-Pesa check, now (P15.6): how many new exceptions.
    return check_all(all_cinemas(), clock_now());
}

def:pub t_stored_verification_file(slug: str, item: str) -> str {
    # The first bytes of a verification file as stored, in hex: sealed, they're "ACF1"
    # (P15.0), never the image's or the PDF's own.
    cinema = open_cinema(slug)
        or [
            c
            for c in all_cinemas()
            if c.slug == slug
        ][0];
    found = verification_record(cinema)["files"].get(item, {});
    data = read_stored_media(found.get("key", "")) or b"";
    return data[:12].hex();
}

def:pub t_send_verification_notices -> int {
    # Sends the queued "viewed or changed" emails to owners, now (P15.0).
    return send_notices_due();
}

def:pub t_delete_due -> int {
    # Deletes the customer accounts whose seven days are up, now (P15.0).
    return delete_due(clock_now());
}

def:pub t_cash_check -> int {
    # The check for cash left uncounted at a shift's end, now (P15.6b).
    return check_all_counted();
}

def:pub t_sim_change(phone: str, outcome: str, amount_cents: int) -> int {
    # M-Pesa changes its mind about `phone`'s pushes (P15.6): their outcome, and the
    # amount it says was paid when not 0. How many pushes.
    changed = 0;
    sim = _simulator();
    if outcome == "forget" {
        # M-Pesa no longer knows them (a prompt too old to ask about). Kept under
        # another name: the simulator numbers new prompts by how many it holds.
        gone = [
            k
            for (k, push) in sim.pushes.items()
            if push.request.phone == phone
        ];
        for k in gone {
            sim.pushes[f"forgotten-{k}"] = sim.pushes.pop(k);
        }
        return len(gone);
    }
    for push in sim.pushes.values() {
        if push.request.phone == phone {
            push.outcome = outcome;
            if amount_cents {
                push.request.amount_cents = amount_cents;
            }
            changed += 1;
        }
    }
    return changed;
}

def:pub t_receipts(slug: str, screening_id: str) -> list[list[str]] {
    # [order reference, receipt] of each M-Pesa payment of the showtime (P15.6).
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return [
            [o.reference, e.receipt] for o in [screening-->[?:Order]]
            for e in [o-->[?:LedgerEntry]]
            if e.kind == "payment" and e.method == "mpesa"
        ];
    } finally {
        restore(me);
    }
}

def:pub t_set_receipt(
    slug: str, screening_id: str, reference: str, receipt: str
) -> bool {
    # Gives an order's M-Pesa payment entry another receipt (P15.6: a receipt twice).
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for o in [screening-->[?:Order]] {
            if o.reference == reference {
                for e in [o-->[?:LedgerEntry]] {
                    if e.kind == "payment" {
                        e.receipt = receipt;
                    }
                }
            }
        }
        commit_now();
    } finally {
        restore(me);
    }
    return True;
}

def:pub t_settle_bills -> int {
    # Settles the invoice payments waiting for M-Pesa now (P15.5).
    return settle_due();
}

def:pub t_remind_bills -> int {
    # Runs the reminders as of now (P15.5): how many invoices were reminded.
    return remind_due(all_cinemas());
}

def:pub t_issue_statements(at: str) -> list[str] {
    # The billing job as of the ISO time `at` (P15.4): the invoice numbers it made.
    return issue_due(all_cinemas(), datetime.fromisoformat(at));
}

def:pub pay_stored(slug: str, screening_id: str) -> list[list[str]] {
    # Every payment stored for the showtime: [reference, state], oldest first.
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[PaymentIntent] = [];
        for o in [screening-->[?:Order]] {
            for p in [o-->[?:PaymentIntent]] {
                found.append(p);
            }
        }
    } finally {
        restore(me);
    }
    ordered = sorted(
        found,
        key=lambda (p: PaymentIntent) -> str { return p.created_at; }  # jac:ignore[W1037]
    );
    return [[p.reference, p.state] for p in ordered];
}

def:pub pay_offer_consent(slug: str, email: str) -> dict[str, str] | None {
    # The offer consent kept for `email` at the cinema (P14.3c).
    cinema = open_cinema(slug);
    assert cinema is not None;
    return consent_of(cinema, email);
}

def:pub pay_terms_shown(slug: str, screening_id: str) -> list[dict[str, str]] {
    # The policy versions each order of the showtime was paid under (P14.3c).
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return [dict(o.terms_shown) for o in [screening-->[?:Order]]];
    } finally {
        restore(me);
    }
}

def _showtime(slug: str, screening_id: str) -> tuple[Tenant, Screening] {
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    return (cinema, screening);
}

def _intent(slug: str, screening_id: str, reference: str) -> PaymentIntent {
    # A showtime's payment; with screening_id "", a snacks-only sale's at any of the
    # cinema's venues (P12.10).
    if not screening_id {
        cinema = tenant_by_id(str(lookup_slug(slug)));
        assert cinema is not None;
        me = node_id(root);
        act_as(cinema.principal_root_id);
        try {
            sold = [
                p for v in [cinema-->[?:Venue]] for o in [v-->[?:Order]]
                for p in [o-->[?:PaymentIntent]]
                if p.reference == reference
            ];
        } finally {
            restore(me);
        }
        assert sold , reference;
        return sold[0];
    }
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[PaymentIntent] = [];
        for o in [screening-->[?:Order]] {
            for p in [o-->[?:PaymentIntent]] {
                if p.reference == reference {
                    found.append(p);
                }
            }
        }
    } finally {
        restore(me);
    }
    assert found , reference;
    return found[0];
}

def _body(
    checkout: str, code: int, receipt: str, cents: int, phone: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # Safaricom's STK callback body (Daraja's format).
    callback: dict[str, any] = {  # jac:ignore[W1037]
        "MerchantRequestID": "sim-merchant",
        "CheckoutRequestID": checkout,
        "ResultCode": code,
        "ResultDesc": "simulated"
    };
    if code == 0 {
        callback["CallbackMetadata"] = {
            "Item": [
                {"Name": "Amount", "Value": cents / 100},
                {"Name": "MpesaReceiptNumber", "Value": receipt},
                {"Name": "TransactionDate", "Value": 20261006120000},
                {"Name": "PhoneNumber", "Value": int(phone)}
            ]
        };
    }
    return {"Body": {"stkCallback": callback}};
}

def:pub pay_callback(slug: str, screening_id: str, reference: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The callback Safaricom would send for this payment now: {token, body} (body None
    # while M-Pesa has nothing to say).
    intent = _intent(slug, screening_id, reference);
    said = _simulator().callback(intent.checkout_request_id);
    body = _body(
        intent.checkout_request_id,
        said.result_code,
        said.receipt,
        said.amount_cents,
        said.phone or intent.phone
    )
        if said is not None
        else None;
    return {"token": intent.callback_token, "body": body};
}

def:pub pay_forged(
    slug: str, screening_id: str, reference: str, code: int, cents: int, receipt: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # A callback that says whatever the test wants: {token, body}.
    intent = _intent(slug, screening_id, reference);
    return {
        "token": intent.callback_token,
        "body": _body(intent.checkout_request_id, code, receipt, cents, intent.phone)
    };
}

def:pub pay_late(slug: str, screening_id: str, reference: str) -> bool {
    _simulator().pay_late(_intent(slug, screening_id, reference).checkout_request_id);
    return True;
}

def:pub pay_resolve -> dict[str, int] {
    return resolve();
}

def:pub pay_process -> int {
    return process_inbox();
}

def:pub pay_expire_order(slug: str, screening_id: str, reference: str) -> bool {
    # Stands in for plan 5.5: the order stops waiting for payment.
    (cinema, screening) = _showtime(slug, screening_id);
    intent = _intent(slug, screening_id, reference);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        order: any = jobj(intent.order_id);  # jac:ignore[W1037]
        (order as Order).status = "expired";
        commit_now();
    } finally {
        restore(me);
    }
    return True;
}

# Test-only (P15.2): each order's frozen fee and its fee ledger, and a refund to the
# customer recorded the way the coming refund screen will (core/payments/fees.jac).
import from core.payments.fees { fee_entries, record_refund }

def:pub t_order_fees(slug: str, screening_id: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return [
            {
                "reference": o.reference,
                "status": o.status,
                "total_cents": o.total_cents,
                "fee_cents": o.fee_cents,
                "fee_detail": o.fee_detail,
                "entries": [[f.kind, f.amount_cents] for f in fee_entries(o)]
            } for o in [screening-->[?:Order]]
        ];
    } finally {
        restore(me);
    }
}

def:pub t_refund(
    slug: str,
    screening_id: str,
    reference: str,
    amount_cents: int,
    method: str,
    # Required: an omitted default arrives as text ("False" is true), JI-060.
    platform_failure: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    # {"refused": why} for a refund the fee ledger won't take (more than is left).
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            o
            for o in [screening-->[?:Order]]
            if o.reference == reference
        ];
        try {
            done = record_refund(
                cinema, found[0], amount_cents, method, platform_failure, "test", ""
            );
        } except ValueError as e {
            return {"refused": str(e)};
        }
        commit_now();
        return done;
    } finally {
        restore(me);
    }
}

def:pub pay_overview(slug: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # What is stored: payments [reference, state, attention], orders' statuses,
    # tickets, open refund tasks, and the seats' stored states.
    (cinema, screening) = _showtime(slug, screening_id);
    seats = slots_of(cinema, screening);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        payments: list[list[str]] = [];
        orders: list[str] = [];
        tickets: list[str] = [];
        refunds: list[str] = [];
        ledger: list[list[any]] = [];  # jac:ignore[W1037]
        balances: list[list[any]] = [];  # jac:ignore[W1037]
        for o in [screening-->[?:Order]] {
            orders.append(o.status);
            entries = [o-->[?:LedgerEntry]];
            for e in entries {
                ledger.append([e.kind, e.amount_cents]);
            }
            balances.append(
                [o.status, o.total_cents, sum([e.amount_cents for e in entries])]
            );
            for t in [o-->[?:Ticket]] {
                tickets.append(t.seat_label);
            }
            for p in [o-->[?:PaymentIntent]] {
                payments.append([p.reference, p.state, p.attention_reason]);
                for r in [p-->[?:RefundTask]] {
                    refunds.append(r.reason);
                }
            }
        }
        states = {x.label: x.state for x in seats};
    } finally {
        restore(me);
    }
    return {
        "payments": sorted(payments),
        "orders": sorted(orders),
        "tickets": sorted(tickets),
        "refunds": sorted(refunds),
        "ledger": sorted(ledger),
        "balances": sorted(balances),
        "seats": states
    };
}

def:pub pay_ticket_codes(slug: str, screening_id: str) -> list[dict[str, str]] {
    # Each stored ticket of the showtime: its seat, reference, QR payload, ids, and who
    # holds its reference's claim (P6.1).
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[dict[str, str]] = [];
        for o in [screening-->[?:Order]] {
            for t in [o-->[?:Ticket]] {
                found.append(
                    {
                        "seat_label": t.seat_label,
                        "reference": t.reference,
                        "qr": t.qr,
                        "ticket_id": node_id(t),
                        "tenant_id": t.tenant_id
                    }
                );
            }
        }
    } finally {
        restore(me);
    }
    for f in found {
        f["claimed_by"] = holder(REFS, f["reference"]) or "";
    }
    return sorted(
        found, key=lambda (f: dict[str, str]) -> str { return f["seat_label"]; }
    );
}

def:pub pay_reserve_collision(taken: str, fresh: str) -> list[str] {
    # Someone holds `taken`; reserving draws it first, then `fresh`. Returns the
    # reference reserved and who holds each (P6.1).
    claim(REFS, taken, "someone-else");
    drawn = iter([taken, fresh]);
    got = reserve_reference("me", 60, lambda -> str { return next(drawn); });
    return [got, holder(REFS, taken) or "", holder(REFS, fresh) or ""];
}

def:pub rd_freeze(slug: str, screening_id: str, minutes: int) -> str {
    # Freezes the clock `minutes` after the showtime starts (negative: before it), for
    # the door's time window (P6.2). Needs AFRICINEMAS_CLOCK_CONTROL=1.
    (_, screening) = _showtime(slug, screening_id);
    at = datetime.fromisoformat(screening.starts_at) + timedelta(minutes=minutes);
    freeze(at);
    return at.isoformat();
}

def:pub rd_unfreeze -> bool {
    reset();
    return True;
}

def _ticket_by_reference(reference: str) -> tuple[Tenant, Ticket] {
    owner = holder(REFS, reference);
    assert owner is not None , reference;
    (tenant_id, ticket_id) = owner.split("|");
    cinema = tenant_by_id(tenant_id);
    assert cinema is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(ticket_id);  # jac:ignore[W1037]
    } finally {
        restore(me);
    }
    assert isinstance(found, Ticket);
    return (cinema, found as Ticket);
}

def:pub rd_ticket(reference: str) -> dict[str, str] {
    # A ticket's stored status and who used it when (P6.2).
    (_, t) = _ticket_by_reference(reference);
    return {"status": t.status, "used_at": t.used_at, "used_by": t.used_by};
}

def:pub rd_set_status(reference: str, status: str) -> bool {
    # Stands in for voiding and refunds, which come later.
    (cinema, t) = _ticket_by_reference(reference);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        t.status = status;
        commit_now();
    } finally {
        restore(me);
    }
    return True;
}

def:pub rd_foreign_reference(reference: str) -> bool {
    # A reference claimed for another cinema's ticket.
    return claim(REFS, reference, "another-tenant-id|another-ticket-id") != "";
}

def:pub tm_send_mail -> int {
    # Runs the ticket mail job once (P6.3); returns how many emails it sent.
    return send_due();
}

def:pub tm_outbox -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The development outbox: every email "sent", oldest first.
    return [
        {"to": m.to, "subject": m.subject, "text": m.text, "images": len(m.images)}
        for m in OUTBOX
    ];
}

def:pub tm_clear_outbox -> bool {
    OUTBOX.clear();
    return True;
}

def:pub bo_ledger(slug: str, screening_id: str) -> list[list[any]] {  # jac:ignore[W1037]
    # The showtime's ledger entries: [kind, amount, method, recorded_by] (P6.5).
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            [e.kind, e.amount_cents, e.method, e.recorded_by]
            for o in [screening-->[?:Order]] for e in [o-->[?:LedgerEntry]]
        ];
    } finally {
        restore(me);
    }
    return found;
}

def:protect audit_refinish(slug: str, event_id: str) -> bool {
    # Tries to finish the cinema's audit event `event_id` again, as "ok" (P7.2): only
    # a pending event is ever finished, so a finished one must not change.
    cinema = lookup_slug(slug);
    _close(Opened(collection=collection_of(str(cinema)), event_id=event_id), "ok", "x");
    return True;
}

def:pub agent_mock(steps: list[any]) -> bool {  # jac:ignore[W1037]
    # The agent's model becomes a MockLLM (P8.1): each step is the model's next answer,
    # a reply text or a tool call {"tool": name, "args": {...}}.
    outputs: list[any] = [];  # jac:ignore[W1037]
    for step in steps {
        if isinstance(step, dict) {
            outputs.append(MockToolCall(tool=step["tool"], args=step.get("args", {})));
        } else {
            outputs.append(str(step));
        }
    }
    agent_module.agent_model = MockLLM(outputs=outputs);
    return True;
}

def _answers(outputs: list[str]) -> any {
    # Claude's scripted answers, in order, each JSON text (ADR-0049): one that isn't
    # JSON, or none left, is a failed call, as a refusal or a provider error would be.
    queue = list(outputs);
    def answer(
        content: any,  # jac:ignore[W1037]
        schema: any,  # jac:ignore[W1037]
        system: str = "",
        effort: str = "",
        timeout: float = 0.0
    ) -> dict[str, any] {  # jac:ignore[W1037]
        if not queue {
            raise ClaudeFailed("no scripted answer left");
        }
        text = queue.pop(0);
        try {
            found: any = json.loads(text);  # jac:ignore[W1037]
        } except ValueError {
            raise ClaudeFailed("the answer wasn't JSON");
        }
        if not isinstance(found, dict) {
            raise ClaudeFailed("the answer wasn't an object");
        }
        return found;
    }
    return answer;
}

def:pub script_brand_kit(plan: str) -> bool {
    # Claude's brand plan (ADR-0049) is this JSON text for every kit drawn, or fails
    # when it is "". The figures are cut from the logo itself, as in production.
    brandkit_module.ask = _answers([plan] * 10 if plan else []);
    return True;
}

def:pub script_storefront_page(answer: str) -> bool {
    # The page writer's model (ADR-0048): every page it writes is this answer, or it
    # fails when the answer is "".
    def written(_logo: bytes, _prompt: str, _model: str) -> str {
        if not answer {
            raise pagecode_module.PageFailed("scripted failure");
        }
        return answer;
    }
    pagecode_module.send = written;
    # No review in tests: no browser, no model (ADR-0050).
    def no_shots(_document: str) -> list[bytes] {
        raise pagereview_module.ReviewSkipped("scripted: no review");
    }
    pagereview_module.shoot = no_shots;
    return True;
}

def:pub script_theme_model(outputs: list[str]) -> bool {
    # Claude's theme answers (ADR-0043, ADR-0049): each output is the next answer, as
    # JSON text; anything else is a failed call.
    suggest_module.ask = _answers(outputs);
    return True;
}

def:pub agent_sent -> dict[str, str] {
    # What the agent sent its (mock) model: the messages and the tools offered.
    model: any = agent_module.agent_model;  # jac:ignore[W1037]
    return {"messages": str(model.sent("messages")), "tools": str(model.sent("tools"))};
}

def:pub agent_offered -> list[str] {
    # The names of the tools offered on the (mock) model's latest call (P8.4).
    model: any = agent_module.agent_model;  # jac:ignore[W1037]
    calls: list[any] = model.sent("tools");  # jac:ignore[W1037]
    if not calls {
        return [];
    }
    return [str(t["function"]["name"]) for t in (calls[-1] or [])];
}

def:pub agent_tool(name: str, args: dict[str, any], holder: str) -> any {  # jac:ignore[W1037]
    # Calls one agent tool directly as the caller, with the conversation's holder.
    fn: any = tool_named(name);  # jac:ignore[W1037]
    token = HOLDER.set(holder);
    try {
        return fn(**args);
    } finally {
        HOLDER.reset(token);
    }
}

# Test-only: the stock calls orders will make (P12.4, used from P12.7).
import from core.catalog.answers { Refused as StockRefused, answer as stock_answer }
import from core.tenancy.open_cinema { open_cinema as stock_cinema }
import from core.snacks.inventory_api { reserve_stock, commit_stock, release_stock }

def _stock_cinema(tenant: str) -> any {  # jac:ignore[W1037]
    found = stock_cinema(tenant);
    if found is None {
        raise StockRefused("not_found", "No such cinema.");
    }
    return found;
}

def:pub t_reserve_snack_stock(
    tenant: str, variant_id: str, venue_id: str, quantity: int
) -> dict[str, any] {  # jac:ignore[W1037]
    def work -> any {  # jac:ignore[W1037]
        if not reserve_stock(_stock_cinema(tenant), variant_id, venue_id, quantity) {
            raise StockRefused("out_of_stock", "Not enough left.");
        }
        return {"ok": True};
    }
    return stock_answer(work);
}

def:pub t_commit_snack_stock(
    tenant: str, variant_id: str, venue_id: str, quantity: int, order_ref: str
) -> dict[str, any] {  # jac:ignore[W1037]
    def work -> any {  # jac:ignore[W1037]
        if not commit_stock(
            _stock_cinema(tenant), variant_id, venue_id, quantity, order_ref
        ) {
            raise StockRefused("out_of_stock", "Not enough on hand.");
        }
        return {"ok": True};
    }
    return stock_answer(work);
}

def:pub t_release_snack_stock(
    tenant: str, variant_id: str, venue_id: str, quantity: int
) -> dict[str, any] {  # jac:ignore[W1037]
    def work -> any {  # jac:ignore[W1037]
        release_stock(_stock_cinema(tenant), variant_id, venue_id, quantity);
        return {"ok": True};
    }
    return stock_answer(work);
}

# Test-only: the AfriCinemas platform's own audit log (P13.1; its console view is 13.3).
import from core.audit.log { events as audit_events }

def:pub t_platform_events -> list[dict[str, str]] {
    return audit_events("platform", "", 50, "");
}

# Test-only: the join link scripts/platform_setup.jac prints for a settings super admin.
import from core.platform.accounts { join_link, SETUP_TTL_S }

def:pub t_platform_setup_link(email: str) -> str {
    return join_link(email, SETUP_TTL_S);
}

# Test-only: as if a new version of the cinema agreement had been published (P15.1);
# "" goes back to the real one.
import from core.legal.agreement { set_current_version }

def:pub t_agreement_version(version: str) -> str {
    set_current_version(version);
    return version;
}

# For the storefront tests that run here, so cinemas can go live (P14.1).
import from core.homepage.home_api {
    get_home_page,
    publish_home_page,
    rollback_home_page
}  # jac:ignore[W2037]

# Test-only: a cinema goes live without the platform's review (P14.1).
import from core.testing.go_live { t_go_live }  # jac:ignore[W2037]
