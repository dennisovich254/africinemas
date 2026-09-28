import from core.health { AppInfo, app_info }
# Every endpoint must be named in the entry import (jac-sv-endpoints). The checker's
# W2037 ("private to module") is a false alarm for this documented pattern: :priv
# endpoints are served, and require a login (tests/api/smoke_tests.jac).
import from core.tenancy.signup { create_cinema, my_cinemas }  # jac:ignore[W2037]

import ".styles.global.css";
import ".styles.fonts.css";
import ".styles.brand.css";
import from .web.AppRoot { AppRoot }

def:pub app -> JsxElement {
    return <AppRoot/>;
}
