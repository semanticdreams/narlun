import 'dart:html' as html;

const _leaveRoomInfoStoragePrefix = 'narlun.leaveRoomInfoSeen.';

String _storageKey(int userId) => '$_leaveRoomInfoStoragePrefix$userId';

bool hasSeenLeaveRoomInfo(int userId) {
  return html.window.localStorage[_storageKey(userId)] == '1';
}

void markLeaveRoomInfoSeen(int userId) {
  html.window.localStorage[_storageKey(userId)] = '1';
}

void clearLeaveRoomInfoStorageForTests() {
  final keysToRemove = html.window.localStorage.keys
      .where((key) => key.startsWith(_leaveRoomInfoStoragePrefix))
      .toList();
  for (final key in keysToRemove) {
    html.window.localStorage.remove(key);
  }
}
