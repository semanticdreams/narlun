import 'dart:async';

import 'http.dart';
import 'models.dart';

class InviteQrCache {
  InviteQrCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<int, InviteLink> _invitesByRoomId = {};
  final Map<int, Future<InviteLink>> _loadTasksByRoomId = {};
  int? _sessionUserId;

  void syncSession(SessionUser? user) {
    final nextUserId = user?.authenticated == true && user?.id != null
        ? user!.id
        : null;
    if (_sessionUserId == nextUserId) {
      return;
    }
    _sessionUserId = nextUserId;
    _invitesByRoomId.clear();
    _loadTasksByRoomId.clear();
  }

  InviteLink? cachedInviteFor({required int roomId}) {
    final invite = _invitesByRoomId[roomId];
    if (invite == null) {
      return null;
    }
    if (!_isInviteUsable(invite)) {
      _invitesByRoomId.remove(roomId);
      return null;
    }
    return invite;
  }

  Future<InviteLink> loadInvite({
    required HttpService httpService,
    required int roomId,
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cachedInvite = cachedInviteFor(roomId: roomId);
      if (cachedInvite != null) {
        return Future.value(cachedInvite);
      }
    }

    final existingTask = _loadTasksByRoomId[roomId];
    if (existingTask != null) {
      return existingTask;
    }

    final task = _createAndStoreInvite(
      httpService: httpService,
      roomId: roomId,
    );
    _loadTasksByRoomId[roomId] = task;
    return task;
  }

  Future<InviteLink> _createAndStoreInvite({
    required HttpService httpService,
    required int roomId,
  }) async {
    try {
      final invite = await httpService.create_invite(roomId: roomId);
      _invitesByRoomId[roomId] = invite;
      return invite;
    } finally {
      _loadTasksByRoomId.remove(roomId);
    }
  }

  bool _isInviteUsable(InviteLink invite) {
    return invite.expiresAt.isAfter(_now());
  }
}
