import from core.health { AppInfo, app_info }
# Domain endpoints declare :protect (authenticated) or :pub (anonymous).
# Plain functions, including scheduled jobs, stay internal (private by default since Jac 0.38).
import from core.tenancy.signup {
    create_cinema,  # jac:ignore[W2037]
    my_cinemas,  # jac:ignore[W2037]
    check_slug  # jac:ignore[W2037]
}
import from core.tenancy.tenant_api {
    my_access,  # jac:ignore[W2037]
    storefront_preview,  # jac:ignore[W2037]
    rename_cinema,  # jac:ignore[W2037]
    set_doors_open,  # jac:ignore[W2037]
    start_shift,  # jac:ignore[W2037]
    end_shift  # jac:ignore[W2037]
}
import from core.tenancy.staff_api {
    invite_staff,  # jac:ignore[W2037]
    accept_invite,  # jac:ignore[W2037]
    list_staff,  # jac:ignore[W2037]
    change_staff_roles,  # jac:ignore[W2037]
    set_staff_status,  # jac:ignore[W2037]
    remove_staff  # jac:ignore[W2037]
}
import from core.catalog.venue_api {
    create_venue,  # jac:ignore[W2037]
    list_venues,  # jac:ignore[W2037]
    update_venue,  # jac:ignore[W2037]
    delete_venue,  # jac:ignore[W2037]
    create_auditorium,  # jac:ignore[W2037]
    rename_auditorium,  # jac:ignore[W2037]
    delete_auditorium  # jac:ignore[W2037]
}
import from core.catalog.layout_api {
    save_layout,  # jac:ignore[W2037]
    publish_layout,  # jac:ignore[W2037]
    list_layouts,  # jac:ignore[W2037]
    get_layout  # jac:ignore[W2037]
}
import from core.catalog.movie_api {
    create_movie,  # jac:ignore[W2037]
    list_movies,  # jac:ignore[W2037]
    get_movie,  # jac:ignore[W2037]
    update_movie,  # jac:ignore[W2037]
    delete_movie,  # jac:ignore[W2037]
    upload_poster,  # jac:ignore[W2037]
    set_trailer,  # jac:ignore[W2037]
    get_poster,  # jac:ignore[W2037]
    get_backdrop,  # jac:ignore[W2037]
    upload_backdrop,  # jac:ignore[W2037]
    remove_backdrop  # jac:ignore[W2037]
}
import from core.catalog.screening_api {
    create_screening,  # jac:ignore[W2037]
    list_screenings,  # jac:ignore[W2037]
    get_screening,  # jac:ignore[W2037]
    set_screening_format,  # jac:ignore[W2037]
    reschedule_screening,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    cancel_screening,  # jac:ignore[W2037]
    publish_screening,  # jac:ignore[W2037]
    unpublish_screening,  # jac:ignore[W2037]
    list_seat_slots,  # jac:ignore[W2037]
    public_screenings
}
import from core.catalog.pricing_api {
    get_price_list,  # jac:ignore[W2037]
    save_price_list,  # jac:ignore[W2037]
    quote_tickets  # jac:ignore[W2037]
}
import from core.theming.branding_api {
    get_branding,  # jac:ignore[W2037]
    save_theme,  # jac:ignore[W2037]
    upload_logo,  # jac:ignore[W2037]
    suggest_themes,  # jac:ignore[W2037]
    draw_brand_kit,  # jac:ignore[W2037]
    design_storefront,  # jac:ignore[W2037]
    set_brand_look,  # jac:ignore[W2037]
    remove_brand_kit,  # jac:ignore[W2037]
    remove_logo,  # jac:ignore[W2037]
    publish_theme,  # jac:ignore[W2037]
    rollback_theme,  # jac:ignore[W2037]
    public_branding
}
import from core.catalog.storefront_api {
    public_home,
    public_movie,
    public_screening,
    public_poster,
    public_home_photo,
    public_backdrop,
    public_venues,
    public_seat_availability,
    public_cinemas
}
import from core.homepage.home_api {
    get_home_page,  # jac:ignore[W2037]
    save_home_page,  # jac:ignore[W2037]
    publish_home_page,  # jac:ignore[W2037]
    rollback_home_page,  # jac:ignore[W2037]
    preview_home_page,  # jac:ignore[W2037]
    upload_home_photo,  # jac:ignore[W2037]
    get_home_photo,  # jac:ignore[W2037]
    remove_home_photo  # jac:ignore[W2037]
}
import from core.booking.hold_api { hold_seats, my_hold, release_hold, extend_hold }
import from core.booking.order_api {
    place_order,
    my_order,
    quote_hold,
    public_ticket_types
}
import from core.booking.redeem_api {
    redeem_ticket,  # jac:ignore[W2037]
    door_showtimes  # jac:ignore[W2037]
}
# Selling at the box office: cash or M-Pesa at the counter (P6.5).
import from core.booking.counter_api {
    counter_showtimes,  # jac:ignore[W2037]
    sell_for_cash,  # jac:ignore[W2037]
    sell_with_mpesa  # jac:ignore[W2037]
}
# The owner's sales report: takings, attendance and the drill-down (P7.1).
import from core.reporting.report_api { sales_report }  # jac:ignore[W2037]
# The cinema's audit log: owners and auditors read it, nobody changes it (P7.2).
import from core.audit.audit_api { audit_log }  # jac:ignore[W2037]
# The AI booking agent: a customer's message in, its reply out (P8.1).
# Storefront accounts: one per cinema, apart from the back office (P8.6c).
import from core.tenancy.storefront_accounts { customer_sign_up, my_storefront_account }
# The snack catalog: categories, products and their variants (P12.1).
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
import from core.snacks.glasses_api { configure_3d_glasses, list_3d_glasses }
# The AfriCinemas platform console: platform staff and their roles (P13.1).
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
# Emailing a cinema's owners when we reply (P13.5b); importing it registers the job.
import from core.support.mail { send_support_mail }  # jac:ignore[W2037]
# Confirming a staff account's email (P14.2); importing the job registers it.
import from core.accounts.email_verification {
    send_email_check,  # jac:ignore[W2037]
    confirm_email,
    email_status,  # jac:ignore[W2037]
    send_email_checks  # jac:ignore[W2037]
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
import from core.booking.more_snacks_api { more_snacks, counter_more_snacks }  # jac:ignore[W2037]
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
import from core.notify.offer_consent {
    my_offers,  # jac:ignore[W2037]
    set_my_offers  # jac:ignore[W2037]
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
import from core.platform.staff_api {
    platform_whoami,  # jac:ignore[W2037]
    platform_join,
    platform_staff,  # jac:ignore[W2037]
    invite_platform_member,  # jac:ignore[W2037]
    set_platform_role,  # jac:ignore[W2037]
    remove_platform_staff  # jac:ignore[W2037]
}
# The storefront's snack menu and a cart's price, from the server only (P12.6).
import from core.snacks.menu_api { public_snacks, price_snacks, public_snack_image }
# Collecting snacks at the snack counter, by the order's pickup code (P12.9).
import from core.snacks.pickup_api {
    snack_pickup,  # jac:ignore[W2037]
    hand_over_snacks  # jac:ignore[W2037]
}
# Connected apps: the apps a customer let book for them, and disconnecting one (P8.6d).
import from core.oauth.connections {
    my_connected_apps,  # jac:ignore[W2037]
    disconnect_app  # jac:ignore[W2037]
}
import from core.agent.agent_api { agent_chat, cinema_chat }
# The MCP server: AfriCinemas in Claude, with a movie card (P8.2). POST /mcp.
import from core.mcp.server { mcp, cinema_mcp }  # jac:ignore[W2037]
# Sign-in for MCP clients such as Claude: OAuth 2.1 with PKCE (P8.6a).
import from core.oauth.provider {
    oauth_server_metadata,
    oauth_resource_metadata_cinema,
    oauth_register,
    oauth_consent_info,  # jac:ignore[W2037]
    oauth_approve,  # jac:ignore[W2037]
    oauth_deny,  # jac:ignore[W2037]
    oauth_token
}  # jac:ignore[W2037]
# The staff home page: setup, today's showtimes, figures and activity (P7.4).
import from core.reporting.staff_home { staff_home, setup_steps, showtime_art }  # jac:ignore[W2037]
# A signed-in customer's saved bookings: "My tickets" (P6.3b).
import from core.booking.customer_tickets {
    save_booking,  # jac:ignore[W2037]
    my_tickets  # jac:ignore[W2037]
}
# The ticket link, resending tickets, and the job that sends ticket emails (P6.3).
import from core.booking.ticket_delivery {
    tickets_by_link,
    resend_tickets,
    send_ticket_mail  # jac:ignore[W2037]
}
import from core.payments.payment_api { start_payment }
# M-Pesa's callback, the payment status, and the job that settles payments (P5.4).
import from core.payments.settlement { my_payment, mpesa_callback, settle_callbacks }  # jac:ignore[W2037]
# Resolving stuck payments and releasing unpaid orders (P5.5).
import from core.payments.resolver { resolve_payments, end_my_order }  # jac:ignore[W2037]
# The hold expiry sweeper (P4.4) runs on a schedule; importing it registers the task.
import from core.booking.sweeper { sweep_holds }  # jac:ignore[W2037]
# The browser tests' super admin join link (P13.1b.a); does nothing unless they set it.
import from core.platform.setup_file { write_setup_links }  # jac:ignore[W2037]
import from core.tenancy.customer_api {
    join_as_customer,  # jac:ignore[W2037]
    my_customer_profile  # jac:ignore[W2037]
}

import ".styles.global.css";
import ".styles.fonts.css";
import ".styles.brand.css";
import ".styles.brandkit.css";
import ".styles.design.css";
import ".styles.landing.css";
import from .web.AppRoot { AppRoot }

def:pub app -> JsxElement {
    return <AppRoot/>;
}
