import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:narlun/bootstrap.dart';
import 'package:narlun/home_tab_storage.dart';
import 'package:narlun/http.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/websocket.dart';

class LiveBackendHarness {
  Directory? _tempDir;
  Process? _redisProcess;
  Process? _backendProcess;
  File? _settingsFile;

  late int redisPort;
  late int backendPort;

  String get apiUrl => 'http://127.0.0.1:$backendPort/api';

  Future<void> start() async {
    _tempDir = await Directory.systemTemp.createTemp('narlun-ui-int-');
    redisPort = await _findFreePort();
    backendPort = await _findFreePort();

    _redisProcess = await Process.start('redis-server', [
      '--save',
      '',
      '--appendonly',
      'no',
      '--port',
      '$redisPort',
      '--dir',
      _tempDir!.path,
    ]);
    _redisProcess!.stdout.listen((_) {});
    _redisProcess!.stderr.listen((_) {});
    await _waitForPort(redisPort);

    await _startBackend();
  }

  Future<void> _startBackend() async {
    _settingsFile = File('${_tempDir!.path}/app_settings.py');
    await _settingsFile!.writeAsString('''
PORT = $backendPort
REDIS_URL = "redis://127.0.0.1:$redisPort/0"
SECRET_KEY = "integration-test-secret"
FRONTEND_ERROR_LOG_PATH = r"${_tempDir!.path}/frontend-errors.jsonl"
''');

    _backendProcess = await Process.start(
      'uv',
      ['run', 'python', '-m', 'app.app'],
      workingDirectory: Directory.current.parent.path,
      environment: {
        ...Platform.environment,
        'APP_SETTINGS': _settingsFile!.path,
      },
    );
    _backendProcess!.stdout.listen((_) {});
    _backendProcess!.stderr.listen((_) {});
    await _waitForHttpReady();
  }

  Future<void> stopBackend() async {
    await _stopProcess(_backendProcess);
    _backendProcess = null;
  }

  Future<void> startBackend() async {
    await _startBackend();
  }

  Future<void> restartBackend() async {
    await stopBackend();
    await startBackend();
  }

  Future<void> dispose() async {
    await _stopProcess(_backendProcess);
    await _stopProcess(_redisProcess);
    if (_tempDir != null && await _tempDir!.exists()) {
      await _tempDir!.delete(recursive: true);
    }
  }

  Future<void> _waitForHttpReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    final client = http.Client();
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final response = await client.get(Uri.parse('$apiUrl/users/me'));
          if (response.statusCode == 200) {
            return;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      client.close();
    }
    throw StateError('Backend did not become ready');
  }

  Future<void> _waitForPort(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        await socket.close();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError('Port $port never opened');
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _stopProcess(Process? process) async {
    if (process == null) {
      return;
    }
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}

class BackendClient {
  final Uri apiBaseUri;
  final http.Client _client = http.Client();

  BackendClient(String apiUrl)
    : apiBaseUri = Uri.parse(apiUrl.endsWith('/') ? apiUrl : '$apiUrl/');

  Future<BackendSession> signupGuest(String username) async {
    final response = await _client.post(
      apiBaseUri.resolve('users/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username}),
    );
    expect(response.statusCode, 200);
    final jwtCookie = _extractJwtCookie(response);
    final user = jsonDecode(response.body) as Map<String, dynamic>;
    return BackendSession(
      this,
      username: username,
      user: user,
      jwtCookie: jwtCookie,
    );
  }

  Future<Map<String, dynamic>> getMe(String jwtCookie) async {
    final response = await _client.get(
      apiBaseUri.resolve('users/me'),
      headers: {'Cookie': jwtCookie},
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile(
    String jwtCookie, {
    String? username,
    String? status,
  }) async {
    final payload = <String, dynamic>{};
    if (username != null) {
      payload['username'] = username;
    }
    if (status != null) {
      payload['status'] = status;
    }
    final response = await _client.post(
      apiBaseUri.resolve('users/update-profile'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode(payload),
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinUser(String jwtCookie, int userId) async {
    final response = await _client.post(
      apiBaseUri.resolve('social/join-user'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode({'user_id': userId}),
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createGroupRoom(
    String jwtCookie,
    String name,
    List<int> userIds,
  ) async {
    final response = await _client.post(
      apiBaseUri.resolve('social/create-room'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode({'name': name, 'user_ids': userIds}),
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestRoomJoin(
    String jwtCookie,
    int roomId,
  ) async {
    final response = await _client.post(
      apiBaseUri.resolve('social/request-room-join'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode({'room_id': roomId}),
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> approveRoomRequest(
    String jwtCookie,
    int roomId,
    int userId,
  ) async {
    final response = await _client.post(
      apiBaseUri.resolve('social/approve-room-request'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode({'room_id': roomId, 'user_id': userId}),
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> rejectRoomRequest(
    String jwtCookie,
    int roomId,
    int userId,
  ) async {
    final response = await _client.post(
      apiBaseUri.resolve('social/reject-room-request'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode({'room_id': roomId, 'user_id': userId}),
    );
    expect(response.statusCode, 204);
  }

  Future<List<dynamic>> getRooms(String jwtCookie) async {
    final response = await _client.get(
      apiBaseUri.resolve('social/get-rooms'),
      headers: {'Cookie': jwtCookie},
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<List<dynamic>> getMessages(String jwtCookie, int roomId) async {
    final response = await _client.post(
      apiBaseUri.resolve('social/get-messages'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode({'room_id': roomId}),
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage(
    String jwtCookie,
    int roomId,
    String body,
  ) async {
    final response = await _client.post(
      apiBaseUri.resolve('social/send-message'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode({'room_id': roomId, 'body': body}),
    );
    expect(response.statusCode, 200);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> markRoomRead(
    String jwtCookie,
    int roomId, {
    String? messageId,
  }) async {
    final payload = <String, Object?>{'room_id': roomId};
    if (messageId != null) {
      payload['message_id'] = messageId;
    }
    final response = await _client.post(
      apiBaseUri.resolve('social/mark-room-read'),
      headers: {'Content-Type': 'application/json', 'Cookie': jwtCookie},
      body: jsonEncode(payload),
    );
    expect(response.statusCode, anyOf(200, 204));
    if (response.statusCode == 204) {
      return null;
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<RawBackendWebSocket> connectWebSocket(String jwtCookie) async {
    final wsBaseUri = apiBaseUri.resolve('ws');
    final wsUri = wsBaseUri.replace(
      scheme: wsBaseUri.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: const {'client_session_id': 'live-test-client'},
    );
    final socket = await WebSocket.connect(
      wsUri.toString(),
      headers: {'Cookie': jwtCookie},
    );
    return RawBackendWebSocket(socket);
  }

  Future<void> signout(String jwtCookie) async {
    final response = await _client.post(
      apiBaseUri.resolve('users/signout'),
      headers: {'Cookie': jwtCookie},
    );
    expect(response.statusCode, 204);
  }

  void close() {
    _client.close();
  }

  String _extractJwtCookie(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) {
      throw StateError('Missing auth cookie');
    }
    return setCookie.split(';').first;
  }
}

class BackendSession {
  final BackendClient client;
  final String username;
  final Map<String, dynamic> user;
  final String jwtCookie;

  BackendSession(
    this.client, {
    required this.username,
    required this.user,
    required this.jwtCookie,
  });

  Future<Map<String, dynamic>> joinUser(int userId) {
    return client.joinUser(jwtCookie, userId);
  }

  Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? status,
  }) {
    return client.updateProfile(jwtCookie, username: username, status: status);
  }

  Future<Map<String, dynamic>> createGroupRoom(String name, List<int> userIds) {
    return client.createGroupRoom(jwtCookie, name, userIds);
  }

  Future<Map<String, dynamic>> requestRoomJoin(int roomId) {
    return client.requestRoomJoin(jwtCookie, roomId);
  }

  Future<Map<String, dynamic>> approveRoomRequest(int roomId, int userId) {
    return client.approveRoomRequest(jwtCookie, roomId, userId);
  }

  Future<void> rejectRoomRequest(int roomId, int userId) {
    return client.rejectRoomRequest(jwtCookie, roomId, userId);
  }

  Future<List<dynamic>> getRooms() {
    return client.getRooms(jwtCookie);
  }

  Future<List<dynamic>> getMessages(int roomId) {
    return client.getMessages(jwtCookie, roomId);
  }

  Future<Map<String, dynamic>> sendMessage(int roomId, String body) {
    return client.sendMessage(jwtCookie, roomId, body);
  }

  Future<Map<String, dynamic>?> markRoomRead(int roomId, {String? messageId}) {
    return client.markRoomRead(jwtCookie, roomId, messageId: messageId);
  }

  Future<void> signout() {
    return client.signout(jwtCookie);
  }
}

class RawBackendWebSocket {
  RawBackendWebSocket(this._socket) {
    _subscription = _socket.listen((event) {
      _buffer.addLast(event as String);
      _waiter?.complete();
      _waiter = null;
    });
  }

  final WebSocket _socket;
  final Queue<String> _buffer = Queue<String>();
  StreamSubscription? _subscription;
  Completer<void>? _waiter;

  Future<void> sendJson(Map<String, Object?> payload) async {
    _socket.add(jsonEncode(payload));
  }

  Future<Map<String, dynamic>> nextJson({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_buffer.isEmpty) {
      _waiter ??= Completer<void>();
      await _waiter!.future.timeout(timeout);
    }
    if (_buffer.isEmpty) {
      throw StateError('No websocket event arrived');
    }
    return jsonDecode(_buffer.removeFirst()) as Map<String, dynamic>;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _socket.close();
  }
}

String randomUsername(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

Future<String> currentFrontendJwtCookie() async {
  final jwtCookie = await loadSessionCookieForTests();
  if (jwtCookie == null || jwtCookie.isEmpty) {
    throw StateError('Frontend auth cookie is missing');
  }
  return jwtCookie;
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<void> pumpUntilNotFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $finder to disappear');
}

Future<void> launchApp(WidgetTester tester, LiveBackendHarness harness) async {
  writeStoredHomeTabIndex(1);
  await clearSessionCookieForTests();
  await initializeApp(environment: 'DEV', apiUrlOverride: harness.apiUrl);
  await tester.pumpWidget(buildNarlunApp());
  await tester.pump();
}

Future<void> signUpThroughUi(WidgetTester tester, String username) async {
  await pumpUntilFound(tester, find.widgetWithText(ElevatedButton, 'Sign Up'));
  await tester.enterText(find.byType(TextField).first, username);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
  await tester.pump();
  await pumpUntilFound(tester, find.text('Rooms'));
}

Future<void> openRoomFromList(WidgetTester tester, String username) async {
  final roomsTab = find.text('Rooms').first;
  if (roomsTab.evaluate().isNotEmpty) {
    await tester.tap(roomsTab);
    await tester.pumpAndSettle();
  }
  await pumpUntilFound(tester, find.text(username));
  await tester.tap(find.text(username).last);
  await tester.pumpAndSettle();
}

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late LiveBackendHarness harness;
  late BackendClient backendClient;

  setUp(() async {
    harness = LiveBackendHarness();
    await harness.start();
    backendClient = BackendClient(harness.apiUrl);
  });

  tearDown(() async {
    clearStoredHomeTabIndexForTests();
    if (locator.isRegistered<WebsocketService>()) {
      await locator<WebsocketService>().close();
      await locator.reset();
    }
    await clearSessionCookieForTests();
    backendClient.close();
    await harness.dispose();
  });

  testWidgets('rooms list updates and live messages arrive from the backend', (
    tester,
  ) async {
    await launchApp(tester, harness);
    final aliceUsername = randomUsername('alice');
    await signUpThroughUi(tester, aliceUsername);

    final aliceJwtCookie = await currentFrontendJwtCookie();
    final alice = await backendClient.getMe(aliceJwtCookie);
    final bob = await backendClient.signupGuest(randomUsername('bob'));

    final room = await bob.joinUser(alice['id'] as int);
    await pumpUntilFound(tester, find.text(bob.username));

    await openRoomFromList(tester, bob.username);
    await bob.sendMessage(room['id'] as int, 'hello from backend');
    await pumpUntilFound(tester, find.text('hello from backend'));
  });

  testWidgets('room deletion while open returns to the room list', (
    tester,
  ) async {
    await launchApp(tester, harness);
    final aliceUsername = randomUsername('alice');
    await signUpThroughUi(tester, aliceUsername);

    final aliceJwtCookie = await currentFrontendJwtCookie();
    final alice = await backendClient.getMe(aliceJwtCookie);
    final bob = await backendClient.signupGuest(randomUsername('bob'));

    await bob.joinUser(alice['id'] as int);
    await pumpUntilFound(tester, find.text(bob.username));
    await openRoomFromList(tester, bob.username);

    await bob.signout();
    await pumpUntilFound(
      tester,
      find.text('This room is no longer available.'),
    );
    await pumpUntilFound(tester, find.text('Rooms'));
    await pumpUntilNotFound(tester, find.text(bob.username));
  });

  testWidgets(
    'guest account signout from another client returns to signup flow',
    (tester) async {
      await launchApp(tester, harness);
      final aliceUsername = randomUsername('alice');
      await signUpThroughUi(tester, aliceUsername);

      final aliceJwtCookie = await currentFrontendJwtCookie();
      await backendClient.signout(aliceJwtCookie);

      await pumpUntilFound(
        tester,
        find.widgetWithText(ElevatedButton, 'Sign Up'),
      );
    },
  );

  testWidgets('user-channel websocket reconnect survives a backend restart', (
    tester,
  ) async {
    await launchApp(tester, harness);
    final aliceUsername = randomUsername('alice');
    await signUpThroughUi(tester, aliceUsername);

    final aliceJwtCookie = await currentFrontendJwtCookie();
    final alice = await backendClient.getMe(aliceJwtCookie);

    await harness.restartBackend();
    await tester.pump(const Duration(seconds: 2));

    final bob = await backendClient.signupGuest(randomUsername('bob'));
    await bob.joinUser(alice['id'] as int);
    await pumpUntilFound(tester, find.text(bob.username));
  });

  testWidgets(
    'user-channel websocket reconnect survives an extended backend outage',
    (tester) async {
      await launchApp(tester, harness);
      final aliceUsername = randomUsername('alice');
      await signUpThroughUi(tester, aliceUsername);

      final aliceJwtCookie = await currentFrontendJwtCookie();
      final alice = await backendClient.getMe(aliceJwtCookie);

      await harness.stopBackend();
      await tester.pump(const Duration(seconds: 4));

      await harness.startBackend();
      await tester.pump(const Duration(seconds: 2));

      final bob = await backendClient.signupGuest(randomUsername('bob'));
      await bob.joinUser(alice['id'] as int);
      await pumpUntilFound(tester, find.text(bob.username));
    },
  );

  testWidgets('room websocket reconnect survives an extended backend outage', (
    tester,
  ) async {
    await launchApp(tester, harness);
    final aliceUsername = randomUsername('alice');
    await signUpThroughUi(tester, aliceUsername);

    final aliceJwtCookie = await currentFrontendJwtCookie();
    final alice = await backendClient.getMe(aliceJwtCookie);
    final bob = await backendClient.signupGuest(randomUsername('bob'));
    final room = await bob.joinUser(alice['id'] as int);

    await pumpUntilFound(tester, find.text(bob.username));
    await openRoomFromList(tester, bob.username);

    await harness.stopBackend();
    await tester.pump(const Duration(seconds: 4));

    await harness.startBackend();
    await tester.pump(const Duration(seconds: 2));

    await bob.sendMessage(room['id'] as int, 'message after restart');
    await pumpUntilFound(tester, find.text('message after restart'));
  });

  testWidgets(
    'room deleted while disconnected closes the room after reconnect',
    (tester) async {
      await launchApp(tester, harness);
      final aliceUsername = randomUsername('alice');
      await signUpThroughUi(tester, aliceUsername);

      final aliceJwtCookie = await currentFrontendJwtCookie();
      final alice = await backendClient.getMe(aliceJwtCookie);
      final bob = await backendClient.signupGuest(randomUsername('bob'));

      await bob.joinUser(alice['id'] as int);
      await pumpUntilFound(tester, find.text(bob.username));
      await openRoomFromList(tester, bob.username);

      await harness.stopBackend();
      await tester.pump(const Duration(seconds: 4));

      await harness.startBackend();
      await bob.signout();
      await tester.pump(const Duration(seconds: 2));

      await pumpUntilFound(
        tester,
        find.text('This room is no longer available.'),
      );
      await pumpUntilFound(tester, find.text('Rooms'));
      await pumpUntilNotFound(tester, find.text(bob.username));
    },
  );

  testWidgets(
    'live backend request flow updates member room list and can be approved in-room',
    (tester) async {
      await launchApp(tester, harness);
      final aliceUsername = randomUsername('alice');
      await signUpThroughUi(tester, aliceUsername);

      final aliceJwtCookie = await currentFrontendJwtCookie();
      final bob = await backendClient.signupGuest(randomUsername('bob'));
      final charlie = await backendClient.signupGuest(
        randomUsername('charlie'),
      );
      final room = await backendClient.createGroupRoom(
        aliceJwtCookie,
        'Coffee crew',
        [bob.user['id'] as int],
      );

      await pumpUntilFound(tester, find.text('Coffee crew'));

      await charlie.requestRoomJoin(room['id'] as int);
      await pumpUntilFound(tester, find.text('1 request'));

      await openRoomFromList(tester, 'Coffee crew');
      await pumpUntilFound(tester, find.text('Pending join requests'));
      await pumpUntilFound(tester, find.text(charlie.username));

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pump();
      await pumpUntilNotFound(tester, find.text('Pending join requests'));

      final charlieRooms = await charlie.getRooms();
      expect(
        charlieRooms.any((candidate) => candidate['id'] == room['id']),
        isTrue,
      );
    },
  );

  testWidgets(
    'live backend approval flow delivers the room to the requester ui',
    (tester) async {
      await launchApp(tester, harness);
      final charlieUsername = randomUsername('charlie');
      await signUpThroughUi(tester, charlieUsername);

      final charlieJwtCookie = await currentFrontendJwtCookie();
      final charlie = await backendClient.getMe(charlieJwtCookie);
      final alice = await backendClient.signupGuest(randomUsername('alice'));
      final bob = await backendClient.signupGuest(randomUsername('bob'));
      final room = await alice.createGroupRoom('Coffee crew', [
        bob.user['id'] as int,
      ]);

      await backendClient.requestRoomJoin(charlieJwtCookie, room['id'] as int);
      expect(find.text('Coffee crew'), findsNothing);

      await alice.approveRoomRequest(room['id'] as int, charlie['id'] as int);

      await pumpUntilFound(tester, find.text('Coffee crew'));
    },
  );

  testWidgets('live backend rejection flow clears the member request badge', (
    tester,
  ) async {
    await launchApp(tester, harness);
    final aliceUsername = randomUsername('alice');
    await signUpThroughUi(tester, aliceUsername);

    final aliceJwtCookie = await currentFrontendJwtCookie();
    final bob = await backendClient.signupGuest(randomUsername('bob'));
    final charlie = await backendClient.signupGuest(randomUsername('charlie'));
    final room = await backendClient.createGroupRoom(
      aliceJwtCookie,
      'Coffee crew',
      [bob.user['id'] as int],
    );

    await pumpUntilFound(tester, find.text('Coffee crew'));
    await charlie.requestRoomJoin(room['id'] as int);
    await pumpUntilFound(tester, find.text('1 request'));

    await bob.rejectRoomRequest(room['id'] as int, charlie.user['id'] as int);

    await pumpUntilNotFound(tester, find.text('1 request'));
  });

  testWidgets(
    'live backend profile updates refresh room titles for other users',
    (tester) async {
      await launchApp(tester, harness);
      final aliceUsername = randomUsername('alice');
      await signUpThroughUi(tester, aliceUsername);

      final aliceJwtCookie = await currentFrontendJwtCookie();
      final alice = await backendClient.getMe(aliceJwtCookie);
      final bob = await backendClient.signupGuest(randomUsername('bob'));

      await bob.joinUser(alice['id'] as int);
      await pumpUntilFound(tester, find.text(bob.username));

      await bob.updateProfile(username: 'renamed-bob');
      await pumpUntilFound(tester, find.text('renamed-bob'));
      await pumpUntilNotFound(tester, find.text(bob.username));
    },
  );

  testWidgets(
    'live backend requester profile updates refresh the pending request panel',
    (tester) async {
      await launchApp(tester, harness);
      final aliceUsername = randomUsername('alice');
      await signUpThroughUi(tester, aliceUsername);

      final aliceJwtCookie = await currentFrontendJwtCookie();
      final bob = await backendClient.signupGuest(randomUsername('bob'));
      final charlie = await backendClient.signupGuest(
        randomUsername('charlie'),
      );
      final room = await backendClient.createGroupRoom(
        aliceJwtCookie,
        'Coffee crew',
        [bob.user['id'] as int],
      );

      await charlie.updateProfile(status: 'Old status');
      await charlie.requestRoomJoin(room['id'] as int);
      await openRoomFromList(tester, 'Coffee crew');
      await pumpUntilFound(tester, find.text('Old status'));

      await charlie.updateProfile(status: 'Updated status');
      await pumpUntilFound(tester, find.text('Updated status'));
      await pumpUntilNotFound(tester, find.text('Old status'));
    },
  );

  testWidgets('typing indicator appears from a live websocket room event', (
    tester,
  ) async {
    await launchApp(tester, harness);
    final aliceUsername = randomUsername('alice');
    await signUpThroughUi(tester, aliceUsername);

    final aliceJwtCookie = await currentFrontendJwtCookie();
    final alice = await backendClient.getMe(aliceJwtCookie);
    final bob = await backendClient.signupGuest(randomUsername('bob'));
    final room = await bob.joinUser(alice['id'] as int);

    await pumpUntilFound(tester, find.text(bob.username));
    await openRoomFromList(tester, bob.username);

    final bobSocket = await backendClient.connectWebSocket(bob.jwtCookie);
    try {
      await bobSocket.sendJson({
        'type': 'subscribe-room',
        'data': {'room_id': room['id']},
      });
      final subscribed = await bobSocket.nextJson();
      expect(subscribed['type'], 'subscribed-room');

      await bobSocket.sendJson({
        'type': 'typing-state',
        'data': {'room_id': room['id'], 'is_typing': true},
      });
      await pumpUntilFound(tester, find.text('${bob.username} is typing...'));
    } finally {
      await bobSocket.close();
    }
  });

  testWidgets('read receipts update in the live room view', (tester) async {
    await launchApp(tester, harness);
    final aliceUsername = randomUsername('alice');
    await signUpThroughUi(tester, aliceUsername);

    final aliceJwtCookie = await currentFrontendJwtCookie();
    final alice = await backendClient.getMe(aliceJwtCookie);
    final bob = await backendClient.signupGuest(randomUsername('bob'));
    final room = await bob.joinUser(alice['id'] as int);

    await pumpUntilFound(tester, find.text(bob.username));
    await openRoomFromList(tester, bob.username);

    await tester.enterText(
      find.byKey(const Key('message-input-field')),
      'hello with receipt',
    );
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pump();
    await pumpUntilFound(tester, find.text('hello with receipt'));

    final bobMessages = await bob.getMessages(room['id'] as int);
    final latestMessageId = bobMessages.first['id'] as String;
    await bob.markRoomRead(room['id'] as int, messageId: latestMessageId);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      final iconFinder = find.byKey(const Key('message-status-icon'));
      if (iconFinder.evaluate().isEmpty) {
        continue;
      }
      final statusIcon = tester.widget<Icon>(iconFinder);
      if (statusIcon.icon == Icons.done_all_rounded &&
          statusIcon.color == const Color(0xFF1D8F8C)) {
        break;
      }
    }

    final statusIcon = tester.widget<Icon>(
      find.byKey(const Key('message-status-icon')),
    );
    expect(statusIcon.icon, Icons.done_all_rounded);
    expect(statusIcon.color, const Color(0xFF1D8F8C));
    expect(find.text('Seen'), findsNothing);
  });
}
