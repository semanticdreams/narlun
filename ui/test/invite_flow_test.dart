// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/invite_accept_view.dart';
import 'package:narlun/invite_qr_cache.dart';
import 'package:narlun/invite_qr_view.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/route_utils.dart';
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
  int createInviteCalls = 0;

  @override
  Future<InviteLink> create_invite({required int roomId}) async {
    createInviteCalls += 1;
    createdInviteRoomId = roomId;
    return inviteToCreate!;
  }

  @override
  Future<RoomSummary> accept_invite(String token) async {
    return acceptedRoom!;
  }
}

String _inviteLinkText(WidgetTester tester) {
  final textField = tester.widget<TextFormField>(
    find.byKey(const Key('invite-link-text')),
  );
  return textField.controller?.text ?? textField.initialValue ?? '';
}

Widget _buildInviteQrApp({
  required _FakeInviteHttpService httpService,
  Widget? home,
  InviteQrCache? inviteQrCache,
}) {
  return MultiProvider(
    providers: [
      Provider<HttpService>.value(value: httpService),
      if (inviteQrCache != null)
        Provider<InviteQrCache>.value(value: inviteQrCache),
      ChangeNotifierProvider(
        create: (_) => MeModel()
          ..setData(
            const SessionUser(authenticated: true, id: 1, username: 'me'),
          ),
      ),
    ],
    child: MaterialApp(home: home ?? const InviteQrView()),
  );
}

void main() {
  testWidgets('global invite QR view renders a nearby onboarding link', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService();

    await tester.pumpWidget(_buildInviteQrApp(httpService: httpService));
    await tester.pumpAndSettle();

    expect(find.text('Open Nearby'), findsWidgets);
    expect(_inviteLinkText(tester), contains('/nearby'));
    expect(find.text('Copy link'), findsOneWidget);
    expect(httpService.createInviteCalls, 0);
    expect(httpService.createdInviteRoomId, isNull);
  });

  testWidgets('room invite QR view requests a room-scoped invite', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService()
      ..inviteToCreate = InviteLink(
        token: 'room-token',
        expiresAt: DateTime.parse('2030-04-05T10:00:00.000Z'),
        roomId: 7,
      );
    final room = RoomSummary(
      id: 7,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'alice'),
        RoomParticipant(id: 3, username: 'bob'),
      ],
    );

    await tester.pumpWidget(
      _buildInviteQrApp(
        httpService: httpService,
        home: InviteQrView(room: room),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite to alice, bob'), findsWidgets);
    expect(_inviteLinkText(tester), contains('/invite/room-token'));
    expect(httpService.createdInviteRoomId, 7);
  });

  testWidgets(
    'room invite QR view reuses the cached invite for the same room',
    (tester) async {
      final httpService = _FakeInviteHttpService()
        ..inviteToCreate = InviteLink(
          token: 'token-123',
          expiresAt: DateTime.parse('2030-04-05T10:00:00.000Z'),
          roomId: 7,
        );
      final inviteQrCache = InviteQrCache()
        ..syncSession(
          const SessionUser(authenticated: true, id: 1, username: 'me'),
        );

      await tester.pumpWidget(
        _buildInviteQrApp(
          httpService: httpService,
          inviteQrCache: inviteQrCache,
          home: const InviteQrView(roomId: 7),
        ),
      );
      await tester.pumpAndSettle();

      expect(_inviteLinkText(tester), contains('/invite/token-123'));
      expect(httpService.createInviteCalls, 1);

      httpService.inviteToCreate = InviteLink(
        token: 'token-456',
        expiresAt: DateTime.parse('2030-04-05T11:00:00.000Z'),
        roomId: 7,
      );

      await tester.pumpWidget(
        _buildInviteQrApp(
          httpService: httpService,
          inviteQrCache: inviteQrCache,
          home: const InviteQrView(roomId: 7),
        ),
      );
      await tester.pumpAndSettle();

      expect(_inviteLinkText(tester), contains('/invite/token-123'));
      expect(_inviteLinkText(tester), isNot(contains('/invite/token-456')));
      expect(httpService.createInviteCalls, 1);
    },
  );

  testWidgets('refresh code replaces the cached invite for the current room', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService()
      ..inviteToCreate = InviteLink(
        token: 'token-123',
        expiresAt: DateTime.parse('2030-04-05T10:00:00.000Z'),
        roomId: 7,
      );
    final inviteQrCache = InviteQrCache()
      ..syncSession(
        const SessionUser(authenticated: true, id: 1, username: 'me'),
      );

    await tester.pumpWidget(
      _buildInviteQrApp(
        httpService: httpService,
        inviteQrCache: inviteQrCache,
        home: const InviteQrView(roomId: 7),
      ),
    );
    await tester.pumpAndSettle();

    expect(_inviteLinkText(tester), contains('/invite/token-123'));

    httpService.inviteToCreate = InviteLink(
      token: 'token-456',
      expiresAt: DateTime.parse('2030-04-05T11:00:00.000Z'),
      roomId: 7,
    );

    await tester.ensureVisible(find.text('Refresh code'));
    await tester.tap(find.text('Refresh code'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(_inviteLinkText(tester), contains('/invite/token-456'));
    expect(httpService.createInviteCalls, 2);
  });

  testWidgets('invite QR view back button pops to the previous route', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService();

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
          onGenerateRoute: (settings) {
            final uri = Uri.parse(settings.name ?? '/');
            if (uri.path == '/') {
              return MaterialPageRoute(
                settings: settings,
                builder: (context) => Scaffold(
                  body: FilledButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          settings: const RouteSettings(name: '/rooms'),
                          builder: (_) =>
                              const Scaffold(body: Text('Rooms page')),
                        ),
                      );
                    },
                    child: const Text('Open rooms'),
                  ),
                ),
              );
            }
            if (uri.path == '/invite') {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => InviteQrView(
                  backToRoute: uri.queryParameters['back_to'],
                  preferPopOnBack: settings.arguments == true,
                ),
              );
            }
            if (uri.path == '/rooms') {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('Rooms page')),
              );
            }
            throw StateError('Unexpected route ${settings.name}');
          },
        ),
      ),
    );

    await tester.tap(find.text('Open rooms'));
    await tester.pumpAndSettle();

    final roomsContext = tester.element(find.text('Rooms page'));
    Navigator.of(
      roomsContext,
    ).pushNamed(inviteQrRouteWithBackTo(backTo: '/rooms'), arguments: true);
    await tester.pumpAndSettle();

    expect(find.text('Open Nearby'), findsWidgets);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Rooms page'), findsOneWidget);
  });

  testWidgets(
    'invite QR view falls back to the room route when opened directly for a room',
    (tester) async {
      final httpService = _FakeInviteHttpService()
        ..inviteToCreate = InviteLink(
          token: 'room-token',
          expiresAt: DateTime.parse('2030-04-05T10:00:00.000Z'),
          roomId: 7,
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
            initialRoute: '/invite?room_id=7',
            onGenerateRoute: (settings) {
              final uri = Uri.parse(settings.name ?? '/');
              if (uri.path == '/') {
                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => const SizedBox.shrink(),
                );
              }
              if (uri.path == '/invite') {
                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => InviteQrView(
                    roomId: int.tryParse(uri.queryParameters['room_id'] ?? ''),
                  ),
                );
              }
              if (settings.name == roomsRouteWithOpenRoom(7)) {
                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => const Scaffold(body: Text('Opened room 7')),
                );
              }
              throw StateError('Unexpected route ${settings.name}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Opened room 7'), findsOneWidget);
    },
  );

  testWidgets('invite accept view routes into the requested room', (
    tester,
  ) async {
    final httpService = _FakeInviteHttpService()
      ..acceptedRoom = RoomSummary(
        id: 42,
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
