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
    public_backdrop
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
