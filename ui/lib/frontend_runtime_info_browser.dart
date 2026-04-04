// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:math';

const _clientSessionStorageKey = 'narlun_client_session_id';

String getOrCreateClientSessionId() {
  try {
    final existing = html.window.sessionStorage[_clientSessionStorageKey];
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
  } catch (_) {
    return _generateClientSessionId();
  }

  final generated = _generateClientSessionId();
  try {
    html.window.sessionStorage[_clientSessionStorageKey] = generated;
  } catch (_) {}
  return generated;
}

String? getUserAgent() {
  final userAgent = html.window.navigator.userAgent;
  if (userAgent.isEmpty) {
    return null;
  }
  return userAgent;
}

Map<String, int>? getScreenInfo() {
  final screen = html.window.screen;
  final width = screen?.width;
  final height = screen?.height;
  if (width == null || height == null) {
    return null;
  }
  return {'w': width, 'h': height};
}

String _generateClientSessionId() {
  final random = Random();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final salt = random.nextInt(1 << 32).toRadixString(16);
  return '$timestamp$salt';
}
