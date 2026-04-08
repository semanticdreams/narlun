import 'external_link_opener_default.dart'
    if (dart.library.html) 'external_link_opener_browser.dart'
    as impl;

Future<bool> openExternalLink(String url) => impl.openExternalLink(url);
