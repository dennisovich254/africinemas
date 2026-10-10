import from core.health { AppInfo, app_info }
# Every endpoint must be named in the entry import (jac-sv-endpoints). The checker's
# W2037 ("private to module") is a false alarm for this documented pattern: :priv
# endpoints are served, and require a login (tests/api/smoke_tests.jac).
import from core.tenancy.signup {
    create_cinema,  # jac:ignore[W2037]
    my_cinemas,  # jac:ignore[W2037]
    check_slug  # jac:ignore[W2037]
}
import from core.tenancy.tenant_api {
    my_access,  # jac:ignore[W2037]
    rename_cinema,  # jac:ignore[W2037]
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
    upload_backdrop,  # jac:ignore[W2037]
    remove_backdrop  # jac:ignore[W2037]
}
import from core.catalog.screening_api {
    create_screening,  # jac:ignore[W2037]
    list_screenings,  # jac:ignore[W2037]
    get_screening,  # jac:ignore[W2037]
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
import from core.agent.agent_api { agent_chat, cinema_chat }
# The MCP server: AfriCinemas in Claude, with a movie card (P8.2). POST /mcp.
import from core.mcp.server { mcp, cinema_mcp }  # jac:ignore[W2037]
# Sign-in for MCP clients such as Claude: OAuth 2.1 with PKCE (P8.6a).
import from core.oauth.provider {
    oauth_server_metadata,
    oauth_resource_metadata,
    oauth_resource_metadata_mcp,
    oauth_resource_metadata_cinema,
    oauth_register,
    oauth_consent_info,  # jac:ignore[W2037]
    oauth_approve,  # jac:ignore[W2037]
    oauth_deny,  # jac:ignore[W2037]
    oauth_token
}  # jac:ignore[W2037]
# The staff home page: setup, today's showtimes, figures and activity (P7.4).
import from core.reporting.staff_home { staff_home, showtime_art }  # jac:ignore[W2037]
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
import from core.tenancy.customer_api {
    join_as_customer,  # jac:ignore[W2037]
    my_customer_profile  # jac:ignore[W2037]
}

import ".styles.global.css";
import ".styles.fonts.css";
import ".styles.brand.css";
import ".styles.landing.css";
import from .web.AppRoot { AppRoot }

def:pub app -> JsxElement {
    return <AppRoot/>;
}
