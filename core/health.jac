"""App identity endpoint, used by smoke tests and uptime checks."""

glob APP_NAME: str = "africinemas",
     APP_VERSION: str = "0.1.0";

obj AppInfo {
    has name: str,
        version: str;
}

def:pub app_info -> AppInfo {
    return AppInfo(name=APP_NAME, version=APP_VERSION);
}
