import from core.health { AppInfo, app_info }
# Every endpoint must be named in the entry import (jac-sv-endpoints). The checker's
# W2037 ("private to module") is a false alarm for this documented pattern: :priv
# endpoints are served, and require a login (tests/api/smoke_tests.jac).
import from core.tenancy.signup { create_cinema, my_cinemas }  # jac:ignore[W2037]
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
