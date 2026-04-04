import 'dart:html' as html;
import 'dart:math';

const _clientIdentityStorageKey = 'narlun.clientId';

Future<String?> readClientIdentity() async {
  final existing = html.window.localStorage[_clientIdentityStorageKey];
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }

  final random = Random.secure();
  final created =
      '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16)}-'
      '${random.nextInt(1 << 32).toRadixString(16)}';
  html.window.localStorage[_clientIdentityStorageKey] = created;
  return created;
}
