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
import from core.tenancy.customer_api {
    join_as_customer,  # jac:ignore[W2037]
    my_customer_profile  # jac:ignore[W2037]
}

import ".styles.global.css";
import ".styles.fonts.css";
import ".styles.brand.css";
import from .web.AppRoot { AppRoot }

def:pub app -> JsxElement {
    return <AppRoot/>;
}
