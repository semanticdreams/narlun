// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:math';

const _clientIdentityStorageKey = 'narlun.clientId';
const _clientIdentityRandomUpperBound = 0x100000000;

Future<String?> readClientIdentity() async {
  final existing = html.window.localStorage[_clientIdentityStorageKey];
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }

  final random = Random.secure();
  final created =
      '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16)}-'
      '${random.nextInt(_clientIdentityRandomUpperBound).toRadixString(16)}';
  html.window.localStorage[_clientIdentityStorageKey] = created;
  return created;
}
