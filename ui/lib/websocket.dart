import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'ws_channel_default.dart'
    if (dart.library.html) 'ws_channel_browser.dart';


class WebsocketService {
  final String baseurl = Environment().config.apiUrl;

  WebSocketChannel? _websocket;
  StreamSubscription? _subscription;
  final StreamController<dynamic> _streamController =
      StreamController.broadcast();
  Future<void>? _connectTask;

  Future<String?> _getJwtCookie() async {
    if (kIsWeb) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt');
  }

  String? _extractJwtValue(String? cookie) {
    if (cookie == null || cookie.isEmpty) {
      return null;
    }
    if (cookie.startsWith('jwt=')) {
      return cookie.substring(4);
    }
    return cookie;
  }

  Future<Map<String, dynamic>?> _buildHeaders() async {
    if (kIsWeb) {
      return null;
    }
    final jwt = _extractJwtValue(await _getJwtCookie());
    if (jwt == null) {
      return null;
    }
    return {'Authorization': 'Bearer $jwt'};
  }

  Future<void> reconnect() async {
    if (_connectTask != null) {
      return _connectTask!;
    }
    final task = _connect();
    _connectTask = task;
    try {
      await task;
    } finally {
      if (identical(_connectTask, task)) {
        _connectTask = null;
      }
    }
  }

  Future<void> _connect() async {
    await close();

    final baseuri = Uri.parse(baseurl);
    final scheme = baseuri.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = Uri(
      scheme: scheme,
      host: baseuri.host,
      port: baseuri.port,
      path: '/api/ws',
    );

    final channel = connectWsChannel(wsUri, headers: await _buildHeaders());
    await channel.ready;
    _websocket = channel;
    _subscription = channel.stream.listen(
      (event) {
        _streamController.add(event);
      },
      onError: (error, stackTrace) {
        _streamController.addError(error, stackTrace);
      },
      onDone: () {
        if (identical(_websocket, channel)) {
          _websocket = null;
          _subscription = null;
        }
      },
    );
  }

  Stream get stream => _streamController.stream;

  Stream<Map<String, dynamic>> eventsStream(String type) => stream
      .map((value) => jsonDecode(value) as Map<String, dynamic>)
      .where((event) => event['type'] == type);

  Stream<Map<String, dynamic>> messagesStream(roomId) => eventsStream('new-messages')
      .where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> roomDeletedStream(roomId) => eventsStream('room-deleted')
      .where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> roomsChangedStream() => eventsStream('rooms-changed');

  Future<void> ensureConnected() async {
    if (_websocket == null) {
      await reconnect();
    }
  }

  Future<void> send(payload) async {
    await ensureConnected();
    _websocket?.sink.add(jsonEncode(payload));
  }

  Future<void> subscribeRoom(roomId) async {
    await send({'type': 'subscribe-room', 'data': {'room_id': roomId}});
  }

  Future<void> unsubscribeRoom(roomId) async {
    if (_websocket == null) {
      return;
    }
    _websocket?.sink
        .add(jsonEncode({'type': 'unsubscribe-room', 'data': {'room_id': roomId}}));
  }

  Future<void> close() async {
    _connectTask = null;
    await _subscription?.cancel();
    _subscription = null;
    await _websocket?.sink.close();
    _websocket = null;
  }
}
