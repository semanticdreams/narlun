// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js_util' as js_util;

List<Map<String, Object?>> consumeBootstrapDiagnostics() {
  final consumer = js_util.getProperty<Object?>(
    html.window,
    '__narlunConsumeBootstrapDiagnostics',
  );
  if (consumer == null) {
    return const [];
  }

  final raw = js_util.callMethod<Object?>(
    html.window,
    '__narlunConsumeBootstrapDiagnostics',
    const [],
  );
  final value = js_util.dartify(raw);
  if (value is! List<Object?>) {
    return const [];
  }

  final diagnostics = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map<Object?, Object?>) {
      continue;
    }
    final event = <String, Object?>{};
    item.forEach((key, nestedValue) {
      if (key is! String) {
        return;
      }
      event[key] = nestedValue;
    });
    diagnostics.add(event);
  }
  return diagnostics;
}
