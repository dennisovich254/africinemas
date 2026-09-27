import from core.health { AppInfo, app_info }

import ".styles.global.css";
import ".styles.fonts.css";
import ".styles.brand.css";
import from .web.AppRoot { AppRoot }

def:pub app -> JsxElement {
    return <AppRoot/>;
}
