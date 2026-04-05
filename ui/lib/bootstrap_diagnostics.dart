import 'bootstrap_diagnostics_default.dart'
    if (dart.library.html) 'bootstrap_diagnostics_browser.dart'
    as impl;

List<Map<String, Object?>> consumeBootstrapDiagnostics() {
  return impl.consumeBootstrapDiagnostics();
}
