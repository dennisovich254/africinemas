import from core.health { AppInfo, app_info }

import ".styles.global.css";
import from .web.AppRoot { AppRoot }

def:pub app -> JsxElement {
    return <AppRoot />;
}
