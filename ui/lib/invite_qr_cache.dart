import 'dart:async';

import 'http.dart';
import 'models.dart';

class InviteQrCache {
  InviteQrCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, InviteLink> _invitesByScope = {};
  final Map<String, Future<InviteLink>> _loadTasksByScope = {};
  int? _sessionUserId;

  void syncSession(SessionUser? user) {
    final nextUserId = user?.authenticated == true && user?.id != null
        ? user!.id
        : null;
    if (_sessionUserId == nextUserId) {
      return;
    }
    _sessionUserId = nextUserId;
    _invitesByScope.clear();
    _loadTasksByScope.clear();
  }

  InviteLink? cachedInviteFor({int? roomId}) {
    final scopeKey = _scopeKey(roomId);
    final invite = _invitesByScope[scopeKey];
    if (invite == null) {
      return null;
    }
    if (!_isInviteUsable(invite)) {
      _invitesByScope.remove(scopeKey);
      return null;
    }
    return invite;
  }

  Future<InviteLink> loadInvite({
    required HttpService httpService,
    int? roomId,
    bool forceRefresh = false,
  }) {
    final scopeKey = _scopeKey(roomId);
    if (!forceRefresh) {
      final cachedInvite = cachedInviteFor(roomId: roomId);
      if (cachedInvite != null) {
        return Future.value(cachedInvite);
      }
    }

    final existingTask = _loadTasksByScope[scopeKey];
    if (existingTask != null) {
      return existingTask;
    }

    final task = _createAndStoreInvite(
      httpService: httpService,
      roomId: roomId,
      scopeKey: scopeKey,
    );
    _loadTasksByScope[scopeKey] = task;
    return task;
  }

  Future<InviteLink> _createAndStoreInvite({
    required HttpService httpService,
    required int? roomId,
    required String scopeKey,
  }) async {
    try {
      final invite = await httpService.create_invite(roomId: roomId);
      _invitesByScope[scopeKey] = invite;
      return invite;
    } finally {
      _loadTasksByScope.remove(scopeKey);
    }
  }

  bool _isInviteUsable(InviteLink invite) {
    return invite.expiresAt.isAfter(_now());
  }

  String _scopeKey(int? roomId) {
    return roomId == null ? 'global' : 'room:$roomId';
  }
}
