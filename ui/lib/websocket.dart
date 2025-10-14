import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'config.dart';

class WebsocketService {
  final String baseurl = Environment().config.apiUrl;

  WebSocketChannel? _websocket;
  StreamController? _streamController;

  WebsocketService() {}

  void reconnect() {
    if (_websocket != null) {
      // TODO this could cause double close when current websocket closed
      close();
    }
    final baseuri = Uri.parse(baseurl);
    final scheme = baseuri.scheme == 'https' ? 'wss' : 'ws';
    final ws_uri = Uri(
        scheme: scheme,
        host: baseuri.host,
        port: baseuri.port,
        path: '/api/ws');
    _websocket = WebSocketChannel.connect(ws_uri);

    _streamController = StreamController.broadcast();
    _streamController!.addStream(_websocket!.stream);
  }

  Stream get stream => _streamController!.stream;

  Stream messagesStream(room_id) =>
      stream.map((value) => jsonDecode(value)).skipWhile((element) =>
          element['type'] != 'new-messages' ||
          element['data']['room_id'] != room_id);

  void send(payload) {
    _websocket!.sink.add(
      jsonEncode(payload),
    );
  }

  void subscribe(data) {
    send({'type': 'subscribe-room', 'data': data});
  }

  void unsubscribe(data) {
    send({'type': 'unsubscribe-room', 'data': data});
  }

  void subscribe_room(room_id) {
    subscribe({'room_id': room_id});
  }

  void unsubscribe_room(room_id) {
    unsubscribe({'room_id': room_id});
  }

  void close() {
    _websocket!.sink.close();
  }
}
