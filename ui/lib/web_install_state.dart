import 'web_install_state_default.dart'
    if (dart.library.html) 'web_install_state_browser.dart'
    as impl;

bool detectInstalledWebApp() => impl.detectInstalledWebApp();

bool isStandaloneWebAppContext() => impl.isStandaloneWebAppContext();
