import 'dart:async';

import 'package:flutter/foundation.dart';

import 'http.dart';
import 'models.dart';

class RoomsFeedModel extends ChangeNotifier {
  RoomsFeedModel({required this.httpService, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const refreshStaleAfter = Duration(seconds: 10);

  final HttpService httpService;
  final DateTime Function() _now;

  final List<RoomSummary> _rooms = [];
  bool _refreshing = false;
  bool _hasLoadedOnce = false;
  String? _errorMessage;
  DateTime? _lastRefreshAttemptAt;
  int? _sessionUserId;
  int _sessionVersion = 0;
  Future<void>? _refreshTask;

  List<RoomSummary> get rooms => List.unmodifiable(_rooms);
  bool get isLoadingInitial => _refreshing && !_hasLoadedOnce;
  bool get hasCachedData => _hasLoadedOnce;
  String? get errorMessage => _hasLoadedOnce ? null : _errorMessage;

  void syncSession(SessionUser? user) {
    final nextUserId = user?.authenticated == true && user?.id != null
        ? user!.id
        : null;
    if (_sessionUserId == nextUserId) {
      return;
    }
    _sessionUserId = nextUserId;
    _sessionVersion += 1;
    _refreshTask = null;
    _rooms.clear();
    _hasLoadedOnce = false;
    _refreshing = false;
    _errorMessage = null;
    _lastRefreshAttemptAt = null;
    notifyListeners();
  }

  Future<void> ensureWarm({bool silentErrors = true}) async {
    if (_sessionUserId == null) {
      return;
    }
    if (!hasCachedData) {
      await refresh(silentErrors: silentErrors);
      return;
    }
    if (_shouldRefreshBecauseStale) {
      unawaited(refresh(silentErrors: silentErrors));
    }
  }

  bool get _shouldRefreshBecauseStale {
    final lastRefreshAttemptAt = _lastRefreshAttemptAt;
    if (lastRefreshAttemptAt == null) {
      return true;
    }
    return _now().difference(lastRefreshAttemptAt) >= refreshStaleAfter;
  }

  Future<void> refresh({bool silentErrors = false}) async {
    if (_sessionUserId == null) {
      return;
    }
    if (_refreshTask != null) {
      return _refreshTask!;
    }
    final refreshSessionVersion = _sessionVersion;
    final refreshSessionUserId = _sessionUserId;
    final task = _runRefresh(
      silentErrors: silentErrors,
      refreshSessionVersion: refreshSessionVersion,
      refreshSessionUserId: refreshSessionUserId,
    );
    _refreshTask = task;
    try {
      await task;
    } finally {
      if (identical(_refreshTask, task)) {
        _refreshTask = null;
      }
    }
  }

  Future<void> _runRefresh({
    required bool silentErrors,
    required int refreshSessionVersion,
    required int? refreshSessionUserId,
  }) async {
    _lastRefreshAttemptAt = _now();
    _refreshing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final resp = await httpService.get_rooms(silentErrors: silentErrors);
      if (!_isCurrentRefresh(
        refreshSessionVersion: refreshSessionVersion,
        refreshSessionUserId: refreshSessionUserId,
      )) {
        return;
      }
      _rooms
        ..clear()
        ..addAll(resp);
      _hasLoadedOnce = true;
      _errorMessage = null;
    } catch (_) {
      if (!_isCurrentRefresh(
        refreshSessionVersion: refreshSessionVersion,
        refreshSessionUserId: refreshSessionUserId,
      )) {
        return;
      }
      _errorMessage = 'Could not refresh rooms right now.';
      rethrow;
    } finally {
      if (_isCurrentRefresh(
        refreshSessionVersion: refreshSessionVersion,
        refreshSessionUserId: refreshSessionUserId,
      )) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentRefresh({
    required int refreshSessionVersion,
    required int? refreshSessionUserId,
  }) {
    return _sessionVersion == refreshSessionVersion &&
        _sessionUserId == refreshSessionUserId;
  }
}
