import 'dart:math';

String? _clientSessionId;

String getOrCreateClientSessionId() {
  return _clientSessionId ??= _generateClientSessionId();
}

String? getUserAgent() {
  return null;
}

Map<String, int>? getScreenInfo() {
  return null;
}

String _generateClientSessionId() {
  final random = Random();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final salt = random.nextInt(1 << 32).toRadixString(16);
  return '$timestamp$salt';
}
