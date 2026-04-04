import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import 'config.dart';
import 'locator.dart';
import 'dialog_service.dart';
import 'websocket.dart';
import 'http_client_default.dart'
    if (dart.library.html) 'http_client_browser.dart'
    as session_http;

Future check_response(data, bodyfunc, DialogService dialogService) async {
  if (data.statusCode == 400) {
    final body = await bodyfunc(data);
    await dialogService.showDialog(
      title: 'Usage error',
      description: body['message'],
    );
    throw InvalidUsage(
      status: data.statusCode,
      message: body['message'],
      code: body['code'],
    );
  } else if (data.statusCode == 500) {
    await dialogService.showDialog(
      title: 'Server error',
      description: 'Contact support.',
    );
    throw ServerError();
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
    return request;
  }

  @override
  Future<http.BaseResponse> interceptResponse({
    required http.BaseResponse response,
  }) async {
    if (response is http.Response) {
      return await check_response(response, (x) {
        return jsonDecode((x as http.Response).body);
      }, dialogService);
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

class ServerError {}

class UnexpectedResponse {
  final status;
  UnexpectedResponse(this.status);
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

  Future signout() async {
    try {
      await client.post(Uri.parse(baseurl + '/users/signout'));
    } finally {
      await clearSessionCookieForTests();
      await websocketService.close();
    }
  }

  Future fetch_me() async {
    final resp = await client.get(Uri.parse(baseurl + '/users/me'));
    final body = jsonDecode(resp.body);
    if (body['authenticated']) {
      await websocketService.reconnect();
    } else {
      await clearSessionCookieForTests();
      await websocketService.close();
    }
    return body;
  }

  Future signup(username) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/users/signup'),
      body: jsonEncode({'username': username}),
    );
    final body = jsonDecode(resp.body);
    if (body['authenticated']) {
      await websocketService.reconnect();
    }
    return body;
  }

  Future signin({username, password}) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/users/signin'),
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body = jsonDecode(resp.body);
    if (body['authenticated']) {
      await websocketService.reconnect();
    }
    return body;
  }

  Future update_profile(data) async {
    final resp = await client.post(
      Uri.parse(baseurl + '/users/update-profile'),
      body: jsonEncode(data),
    );
    final body = jsonDecode(resp.body);
    return body;
  }

  Future upload_profile_picture(data) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(baseurl + '/users/upload-profile-picture'),
    );
    final multipart_file = http.MultipartFile.fromBytes('file', data);
    request.files.add(multipart_file);
    final resp = await client.send(request);
    final bodyfunc = (x) async {
      return jsonDecode(await x.stream.bytesToString());
    };
    await check_response(resp, bodyfunc, dialogService);
    return bodyfunc(resp);
  }

  Future delete_account() async {
    try {
      await client.delete(Uri.parse(baseurl + '/users/me'));
    } finally {
      await clearSessionCookieForTests();
      await websocketService.close();
    }
  }

  Future checkin(lat, lon) async {
    final data = {'lat': lat, 'lon': lon};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/checkin'),
      body: jsonEncode(data),
    );
    final body = jsonDecode(resp.body);
    return body;
  }

  Future join_user(user_id) async {
    final data = {'user_id': user_id};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/join-user'),
      body: jsonEncode(data),
    );
    final body = jsonDecode(resp.body);
    return body;
  }

  Future get_rooms() async {
    final resp = await client.get(Uri.parse(baseurl + '/social/get-rooms'));
    final body = jsonDecode(resp.body);
    return body;
  }

  Future get_messages(room_id) async {
    final data = {'room_id': room_id};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/get-messages'),
      body: jsonEncode(data),
    );
    final body = jsonDecode(resp.body);
    return body;
  }

  Future send_message(room_id, message_body) async {
    final data = {'room_id': room_id, 'body': message_body};
    final resp = await client.post(
      Uri.parse(baseurl + '/social/send-message'),
      body: jsonEncode(data),
    );
    final body = jsonDecode(resp.body);
    return body;
  }
}

Future<String?> loadSessionCookieForTests() => session_http.readSessionCookie();

Future<void> clearSessionCookieForTests() => session_http.clearSessionCookie();
