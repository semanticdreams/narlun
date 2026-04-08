import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import 'client_observability.dart';
import 'config.dart';
import 'locator.dart';
import 'dialog_service.dart';
import 'frontend_runtime_info.dart';
import 'models.dart';
import 'push_subscription_endpoint_default.dart'
    if (dart.library.html) 'push_subscription_endpoint_browser.dart'
    as push_subscription;
import 'websocket.dart';
import 'http_client_default.dart'
    if (dart.library.html) 'http_client_browser.dart'
    as session_http;

const silentErrorHeader = 'x-narlun-silent-errors';
Future check_response(
  data,
  bodyfunc,
  DialogService dialogService, {
  bool showDialogs = true,
}) async {
  if (data.statusCode == 400) {
    final body = await bodyfunc(data);
    if (showDialogs) {
      await dialogService.showDialog(
        title: 'Usage error',
        description: body['message'],
      );
    }
    throw InvalidUsage(
      status: data.statusCode,
      message: body['message'],
      code: body['code'],
    );
  } else if (data.statusCode == 401) {
    throw UnauthorizedResponse();
  } else if (data.statusCode == 403) {
    throw ForbiddenResponse();
  } else if (data.statusCode == 404) {
    throw NotFoundResponse();
  } else if (data.statusCode == 413) {
    if (showDialogs) {
      await dialogService.showDialog(
        title: 'Picture too large',
        description:
            'That picture is too large to upload. Choose a smaller image and try again.',
      );
    }
    throw PayloadTooLargeResponse();
  } else if (data.statusCode >= 500 && data.statusCode <= 599) {
    if (showDialogs) {
      await dialogService.showDialog(
        title: 'Server error',
        description: 'The server could not complete that request. Try again.',
      );
    }
    throw ServerError(data.statusCode);
  } else if (data.statusCode == 200 || data.statusCode == 204) {
    return data;
  } else {
    throw UnexpectedResponse(data.statusCode);
  }
}

class ErrorInterceptor implements InterceptorContract {
  final DialogService dialogService;

  ErrorInterceptor(this.dialogService);

  @override
  Future<bool> shouldInterceptRequest() async => true;

  @override
  Future<bool> shouldInterceptResponse() async => true;

  @override
  Future<http.BaseRequest> interceptRequest({
    required http.BaseRequest request,
  }) async {
    request.headers.putIfAbsent(
      clientSessionHeader,
      getOrCreateClientSessionId,
    );
    return request;
  }

  @override
  Future<http.BaseResponse> interceptResponse({
    required http.BaseResponse response,
  }) async {
    final showDialogs = response.request?.headers[silentErrorHeader] != '1';
    if (response is http.Response) {
      return await check_response(
        response,
        (x) {
          return jsonDecode((x as http.Response).body);
        },
        dialogService,
        showDialogs: showDialogs,
      );
    }
    return response;
  }
}

class InvalidUsage {
  final status;
  final message;
  final code;

  InvalidUsage({
    required this.status,
    required this.message,
    required this.code,
  });
}

class ServerError {
  final int status;

  ServerError(this.status);
}

class UnexpectedResponse {
  final status;
  UnexpectedResponse(this.status);
}

class UnauthorizedResponse extends UnexpectedResponse {
  UnauthorizedResponse() : super(401);
}

class ForbiddenResponse extends UnexpectedResponse {
  ForbiddenResponse() : super(403);
}

class NotFoundResponse extends UnexpectedResponse {
  NotFoundResponse() : super(404);
}

class PayloadTooLargeResponse extends UnexpectedResponse {
  PayloadTooLargeResponse() : super(413);
}

bool isAlreadyPresentedActionError(Object error) {
  return error is InvalidUsage ||
      error is ServerError ||
      error is PayloadTooLargeResponse;
}

String describeActionError(
  Object error, {
  required String fallbackDescription,
}) {
  if (error is InvalidUsage) {
    return '${error.message}';
  }
  if (error is PayloadTooLargeResponse) {
    return 'That picture is too large to upload. Choose a smaller image and try again.';
  }
  if (error is UnauthorizedResponse) {
    return 'Your session has ended. Please sign in again.';
  }
  if (error is ServerError) {
    return 'The server could not complete that request. Try again.';
  }
  if (error is UnexpectedResponse) {
    return 'The request failed with status ${error.status}. Please try again.';
  }
  if (error is http.ClientException) {
    return 'The app could not reach the server. Check your connection and try again.';
  }
  return fallbackDescription;
}

Future<void> showActionErrorDialog(
  DialogService dialogService, {
  required String title,
  required Object error,
  required String fallbackDescription,
}) async {
  if (isAlreadyPresentedActionError(error)) {
    return;
  }
  await dialogService.showDialog(
    title: title,
    description: describeActionError(
      error,
      fallbackDescription: fallbackDescription,
    ),
  );
}

class HttpService {
  final WebsocketService websocketService;
  final DialogService dialogService;
  final String baseurl = Environment().config.apiUrl;

  late http.Client client;

  HttpService({
    WebsocketService? websocketService,
    DialogService? dialogService,
    http.Client? client,
  }) : websocketService = websocketService ?? locator<WebsocketService>(),
       dialogService = dialogService ?? locator<DialogService>() {
    this.client = InterceptedClient.build(
      interceptors: [ErrorInterceptor(this.dialogService)],
      client: client ?? session_http.createHttpClient(),
    );
  }

  Map<String, String> _requestHeaders({bool silentErrors = false}) {
    final headers = <String, String>{};
    if (silentErrors) {
      headers[silentErrorHeader] = '1';
    }
    return headers;
  }

  Future<void> clearLocalSession() async {
    await clearSessionCookieForTests();
    await websocketService.close();
  }

  void close() {
    client.close();
  }

  Future signout() async {
    final pushEndpoint = await push_subscription
        .readCurrentPushSubscriptionEndpoint();
    try {
      await client.post(
        Uri.parse(baseurl + '/users/signout'),
        body: pushEndpoint == null
            ? null
            : jsonEncode({'push_endpoint': pushEndpoint}),
      );
      await clearLocalSession();
    } on UnauthorizedResponse {
      await clearLocalSession();
      rethrow;
    }
  }

  Future<String?> submit_feedback({
    required String message,
    required String source,
    String? route,
    Map<String, Object?>? details,
    bool silentErrors = false,
  }) async {
    final response = await client.post(
      Uri.parse('$baseurl/users/feedback'),
      headers: {
        'Content-Type': 'application/json',
        ..._requestHeaders(silentErrors: silentErrors),
      },
      body: jsonEncode({
        'app': 'narlun-ui',
        'release': const String.fromEnvironment('APP_RELEASE'),
        'message': message,
        'source': source,
        'route': route,
        'details': details,
        'client_session_id': getOrCreateClientSessionId(),
        'user_agent': getUserAgent(),
        'screen': getScreenInfo(),
      }),
    );
    return response.headers['x-request-id'] ?? response.headers['X-Request-ID'];
  }

  Future<SessionUser> fetch_me({
    bool silentErrors = false,
    bool reconnectWebsocket = true,
  }) async {
    try {
      final resp = await client.get(
        Uri.parse(baseurl + '/users/me'),
        headers: _requestHeaders(silentErrors: silentErrors),
      );
      final body = SessionUser.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>,
      );
      if (body.authenticated && reconnectWebsocket) {
        await websocketService.reconnect();
      } else {
        if (!body.authenticated) {
          await clearLocalSession();
        }
      }
      return body;
    } on UnauthorizedResponse {
      await clearLocalSession();
      return SessionUser.unauthenticated();
    }
  }

  Future<SessionUser> signup(username) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/users/signup'),
      body: jsonEncode({'username': username}),
    );
    final body = SessionUser.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
    if (body.authenticated) {
      await websocketService.reconnect();
    }
    return body;
  }

  Future<SessionUser> signin({username, password}) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/users/signin'),
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body = SessionUser.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
    if (body.authenticated) {
      await websocketService.reconnect();
    }
    return body;
  }

  Future<SessionUser> claimInstallSession(
    String token, {
    bool silentErrors = false,
  }) async {
    final resp = await client.post(
      Uri.parse('$baseurl/users/claim-install-session'),
      headers: {
        'Content-Type': 'application/json',
        ..._requestHeaders(silentErrors: silentErrors),
      },
      body: jsonEncode({'token': token}),
    );
    final body = SessionUser.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
    if (body.authenticated) {
      await websocketService.reconnect();
    }
    return body;
  }

  Future<SessionUser> update_profile(data) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/users/update-profile'),
      body: jsonEncode(data),
    );
    return SessionUser.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<String> upload_profile_picture(List<int> data) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(baseurl + '/users/upload-profile-picture'),
    );
    final multipart_file = http.MultipartFile.fromBytes(
      'file',
      data,
      filename: 'avatar-upload',
    );
    request.files.add(multipart_file);
    final resp = await client.send(request);
    final bodyfunc = (x) async {
      return jsonDecode(await x.stream.bytesToString());
    };
    await check_response(resp, bodyfunc, dialogService);
    final body = await bodyfunc(resp) as Map<String, dynamic>;
    return body['picture'] as String;
  }

  Future delete_account() async {
    try {
      await client.delete(Uri.parse(baseurl + '/users/me'));
      await clearLocalSession();
    } on UnauthorizedResponse {
      await clearLocalSession();
      rethrow;
    }
  }

  Future<List<NearbyItem>> checkin(lat, lon) async {
    final data = {'lat': lat, 'lon': lon};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/checkin'),
      body: jsonEncode(data),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return NearbyItem.listFromJson(body['nearby'] as List<dynamic>);
  }

  Future<int> join_user(user_id) async {
    final data = {'user_id': user_id};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/join-user'),
      body: jsonEncode(data),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['id'] as int;
  }

  Future<RoomSummary> create_room({
    String name = '',
    List<int> userIds = const [],
  }) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/social/create-room'),
      body: jsonEncode({'name': name, 'user_ids': userIds}),
    );
    return RoomSummary.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<RoomSummary> request_room_join(room_id) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/social/request-room-join'),
      body: jsonEncode({'room_id': room_id}),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return RoomSummary.fromJson(body['room'] as Map<String, dynamic>);
  }

  Future<InviteLink> create_invite({int? roomId}) async {
    final payload = <String, dynamic>{};
    if (roomId != null) {
      payload['room_id'] = roomId;
    }
    final resp = await client.post(
      Uri.parse(baseurl + '/social/create-invite'),
      body: jsonEncode(payload),
    );
    return InviteLink.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<RoomSummary> accept_invite(String token) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/social/accept-invite'),
      body: jsonEncode({'token': token}),
    );
    return RoomSummary.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<List<RoomSummary>> get_rooms({bool silentErrors = false}) async {
    final resp = await client.get(
      Uri.parse(baseurl + '/social/get-rooms'),
      headers: _requestHeaders(silentErrors: silentErrors),
    );
    return RoomSummary.listFromJson(jsonDecode(resp.body) as List<dynamic>);
  }

  Future<List<RoomJoinRequest>> get_room_requests(
    room_id, {
    bool silentErrors = false,
  }) async {
    final resp = await client.get(
      Uri.parse(baseurl + '/social/get-room-requests?room_id=$room_id'),
      headers: _requestHeaders(silentErrors: silentErrors),
    );
    return RoomJoinRequest.listFromJson(jsonDecode(resp.body) as List<dynamic>);
  }

  Future<RoomSummary> approve_room_request(room_id, user_id) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/social/approve-room-request'),
      body: jsonEncode({'room_id': room_id, 'user_id': user_id}),
    );
    return RoomSummary.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> reject_room_request(room_id, user_id) async {
    await client.post(
      Uri.parse(baseurl + '/social/reject-room-request'),
      body: jsonEncode({'room_id': room_id, 'user_id': user_id}),
    );
  }

  Future<void> leave_room(room_id) async {
    await client.post(
      Uri.parse(baseurl + '/social/leave-room'),
      body: jsonEncode({'room_id': room_id}),
    );
  }

  Future<List<ChatMessage>> get_messages(
    room_id, {
    bool silentErrors = false,
  }) async {
    final data = {'room_id': room_id};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/get-messages'),
      headers: _requestHeaders(silentErrors: silentErrors),
      body: jsonEncode(data),
    );
    return ChatMessage.listFromJson(jsonDecode(resp.body) as List<dynamic>);
  }

  Future<RoomSummary> update_room_settings(
    room_id, {
    required bool pushMuted,
  }) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/social/update-room-settings'),
      body: jsonEncode({'room_id': room_id, 'push_muted': pushMuted}),
    );
    return RoomSummary.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<ChatMessage> send_message(room_id, message_body) async {
    final data = {'room_id': room_id, 'body': message_body};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/send-message'),
      body: jsonEncode(data),
    );
    return ChatMessage.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> mark_room_read(
    room_id, {
    String? messageId,
    bool silentErrors = true,
  }) async {
    final data = <String, Object?>{'room_id': room_id};
    if (messageId != null && messageId.isNotEmpty) {
      data['message_id'] = messageId;
    }
    await client.post(
      Uri.parse(baseurl + '/social/mark-room-read'),
      headers: _requestHeaders(silentErrors: silentErrors),
      body: jsonEncode(data),
    );
  }
}

Future<String?> loadSessionCookieForTests() => session_http.readSessionCookie();

Future<void> clearSessionCookieForTests() => session_http.clearSessionCookie();
