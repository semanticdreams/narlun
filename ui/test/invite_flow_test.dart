// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/invite_accept_view.dart';
import 'package:narlun/invite_qr_view.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/websocket.dart';

class _DummyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}

class _FakeWebsocketService extends WebsocketService {
  _FakeWebsocketService()
    : super(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => throw UnimplementedError(),
      );
}

class _FakeInviteHttpService extends HttpService {
  _FakeInviteHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  InviteLink? inviteToCreate;
  RoomSummary? acceptedRoom;
  int? createdInviteRoomId;

  @override
  Future<InviteLink> create_invite({int? roomId}) async {
    createdInviteRoomId = roomId;
    return inviteToCreate!;
  }

  @override
  Future<RoomSummary> accept_invite(String token) async {
    return acceptedRoom!;
  }
}

void main() {
  testWidgets('invite QR view renders the invite link', (tester) async {
    final httpService = _FakeInviteHttpService()
      ..inviteToCreate = InviteLink(
        token: 'token-123',
        expiresAt: DateTime.parse('2026-04-05T10:00:00.000Z'),
        roomId: 7,
      );

    await tester.pumpWidget(
      Provider<HttpService>.value(
        value: httpService,
        child: const MaterialApp(home: InviteQrView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite someone'), findsWidgets);
    final textField = tester.widget<TextFormField>(
      find.byKey(const Key('invite-link-text')),
    );
    expect(textField.controller?.text, contains('/invite/token-123'));
    expect(find.text('Copy link'), findsOneWidget);
    expect(httpService.createdInviteRoomId, isNull);
  });

  testWidgets('room invite QR view requests a room-scoped invite', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService()
      ..inviteToCreate = InviteLink(
        token: 'room-token',
        expiresAt: DateTime.parse('2026-04-05T10:00:00.000Z'),
        roomId: 7,
      );
    final room = RoomSummary(
      id: 7,
      isGroup: true,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'alice'),
        RoomParticipant(id: 3, username: 'bob'),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(home: InviteQrView(room: room)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite to alice, bob'), findsWidgets);
    expect(httpService.createdInviteRoomId, 7);
  });

  testWidgets('room invite QR view can be restored from a room id route', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService()
      ..inviteToCreate = InviteLink(
        token: 'room-token',
        expiresAt: DateTime.parse('2026-04-05T10:00:00.000Z'),
        roomId: 7,
      );

    await tester.pumpWidget(
      Provider<HttpService>.value(
        value: httpService,
        child: const MaterialApp(home: InviteQrView(roomId: 7)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite to this conversation'), findsWidgets);
    expect(httpService.createdInviteRoomId, 7);
  });

  testWidgets('invite accept view routes into the requested room', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService()
      ..acceptedRoom = RoomSummary(
        id: 42,
        isGroup: false,
        updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
        participants: const [
          RoomParticipant(id: 1, username: 'me'),
          RoomParticipant(id: 2, username: 'other'),
        ],
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(
          home: const InviteAcceptView(token: 'token-123'),
          onGenerateRoute: (settings) {
            if (settings.name == '/rooms?open_room=42') {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('Opened room 42')),
              );
            }
            if (settings.name == '/' || settings.name == null) {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const SizedBox.shrink(),
              );
            }
            throw StateError('Unexpected route ${settings.name}');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Opened room 42'), findsOneWidget);
  });
}
