import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:narlun/websocket.dart';

class FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  final Completer<void> _readyCompleter = Completer<void>();
  final List<String> sent = [];

  FakeWebSocketChannel() {
    _readyCompleter.complete();
  }

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  late final WebSocketSink sink = _FakeWebSocketSink(this);

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  void sendServerEvent(Map<String, dynamic> event) {
    _controller.add(jsonEncode(event));
  }

  Future<void> closeFromServer() async {
    await _controller.close();
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  final FakeWebSocketChannel channel;

  _FakeWebSocketSink(this.channel);

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  void add(dynamic data) {
    channel.sent.add(data as String);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await channel.closeFromServer();
  }

  @override
  Future<void> get done => channel._controller.done;
}

void main() {
  test(
    'reconnects and resubscribes desired rooms after an unexpected disconnect',
    () async {
      final channels = <FakeWebSocketChannel>[
        FakeWebSocketChannel(),
        FakeWebSocketChannel(),
      ];
      var channelIndex = 0;

      final service = WebsocketService(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => channels[channelIndex++],
        reconnectDelay: const Duration(milliseconds: 10),
        maxReconnectDelay: const Duration(milliseconds: 20),
        subscriptionTimeout: const Duration(milliseconds: 200),
      );

      final connectionEvents = <String>[];
      final connectionSubscription = service.connectionEvents.listen(
        connectionEvents.add,
      );

      final subscribeFuture = service.subscribeRoom(7);
      await Future<void>.delayed(Duration.zero);
      expect(channels[0].sent, hasLength(1));
      expect(jsonDecode(channels[0].sent.single), {
        'type': 'subscribe-room',
        'data': {'room_id': 7},
      });

      channels[0].sendServerEvent({
        'type': 'subscribed-room',
        'data': {'room_id': 7},
      });
      await subscribeFuture;
      await Future<void>.delayed(Duration.zero);
      expect(connectionEvents, contains('connected'));

      await channels[0].closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(channels[1].sent, hasLength(1));
      expect(jsonDecode(channels[1].sent.single), {
        'type': 'subscribe-room',
        'data': {'room_id': 7},
      });

      channels[1].sendServerEvent({
        'type': 'subscribed-room',
        'data': {'room_id': 7},
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(connectionEvents, contains('disconnected'));
      expect(connectionEvents, contains('reconnected'));

      await connectionSubscription.cancel();
      await service.close();
    },
  );

  test(
    'keeps retrying reconnects after repeated connection failures',
    () async {
      final firstChannel = FakeWebSocketChannel();
      final recoveredChannel = FakeWebSocketChannel();
      final outcomes = <Object>[
        firstChannel,
        StateError('backend unavailable'),
        StateError('backend still unavailable'),
        recoveredChannel,
      ];
      var connectCount = 0;

      final service = WebsocketService(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) {
          connectCount += 1;
          final outcome = outcomes.removeAt(0);
          if (outcome is FakeWebSocketChannel) {
            return outcome;
          }
          throw outcome;
        },
        reconnectDelay: const Duration(milliseconds: 10),
        maxReconnectDelay: const Duration(milliseconds: 20),
        subscriptionTimeout: const Duration(milliseconds: 200),
      );

      final subscribeFuture = service.subscribeRoom(9);
      await Future<void>.delayed(Duration.zero);
      firstChannel.sendServerEvent({
        'type': 'subscribed-room',
        'data': {'room_id': 9},
      });
      await subscribeFuture;

      await firstChannel.closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(connectCount, 4);
      expect(recoveredChannel.sent, hasLength(1));
      expect(jsonDecode(recoveredChannel.sent.single), {
        'type': 'subscribe-room',
        'data': {'room_id': 9},
      });

      recoveredChannel.sendServerEvent({
        'type': 'subscribed-room',
        'data': {'room_id': 9},
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await service.close();
    },
  );

  test(
    'room access denial during reconnect drops the room without wedging the socket',
    () async {
      final firstChannel = FakeWebSocketChannel();
      final secondChannel = FakeWebSocketChannel();
      final channels = <FakeWebSocketChannel>[firstChannel, secondChannel];
      var channelIndex = 0;

      final service = WebsocketService(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => channels[channelIndex++],
        reconnectDelay: const Duration(milliseconds: 10),
        maxReconnectDelay: const Duration(milliseconds: 20),
        subscriptionTimeout: const Duration(milliseconds: 200),
      );

      final roomDeletedEvents = <Map<String, dynamic>>[];
      final roomDeletedSubscription = service
          .roomDeletedStream(5)
          .listen(roomDeletedEvents.add);

      final subscribeFuture = service.subscribeRoom(5);
      await Future<void>.delayed(Duration.zero);
      firstChannel.sendServerEvent({
        'type': 'subscribed-room',
        'data': {'room_id': 5},
      });
      await subscribeFuture;

      await firstChannel.closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(jsonDecode(secondChannel.sent.single), {
        'type': 'subscribe-room',
        'data': {'room_id': 5},
      });
      secondChannel.sendServerEvent({
        'type': 'error',
        'data': {
          'code': 'room-access-denied',
          'message': 'Cannot subscribe to that room',
          'room_id': 5,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(roomDeletedEvents, [
        {
          'type': 'room-deleted',
          'data': {'room_id': 5},
        },
      ]);

      final sentCountBeforeEnsureConnected = secondChannel.sent.length;
      await service.ensureConnected();
      expect(channelIndex, 2);
      expect(secondChannel.sent.length, sentCountBeforeEnsureConnected);

      await roomDeletedSubscription.cancel();
      await service.close();
    },
  );

  test(
    'signout event stops reconnect attempts and clears desired subscriptions',
    () async {
      final channel = FakeWebSocketChannel();
      var connectCount = 0;

      final service = WebsocketService(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) {
          connectCount += 1;
          return channel;
        },
        reconnectDelay: const Duration(milliseconds: 10),
        maxReconnectDelay: const Duration(milliseconds: 20),
        subscriptionTimeout: const Duration(milliseconds: 200),
      );

      final subscribeFuture = service.subscribeRoom(5);
      await Future<void>.delayed(Duration.zero);
      channel.sendServerEvent({
        'type': 'subscribed-room',
        'data': {'room_id': 5},
      });
      await subscribeFuture;

      channel.sendServerEvent({
        'type': 'signout',
        'data': {'type': 'signout'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await channel.closeFromServer();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(connectCount, 1);
      await service.close();
    },
  );
}
