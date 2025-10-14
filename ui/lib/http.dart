import 'dart:convert';
import 'dart:io';
import 'dart:html';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import 'config.dart';

import 'locator.dart';
import 'dialog_service.dart';

import 'websocket.dart';

import 'http_client_default.dart'
    if (dart.library.html) 'http_client_browser.dart';

WebsocketService _websocketService = locator<WebsocketService>();

DialogService _dialogService = locator<DialogService>();

Future check_response(data, bodyfunc) async {
  if (data.statusCode == 400) {
    final body = await bodyfunc(data);
    await _dialogService.showDialog(
        title: 'Usage error', description: body['message']);
    throw InvalidUsage(
        status: data.statusCode, message: body['message'], code: body['code']);
  } else if (data.statusCode == 500) {
    await _dialogService.showDialog(
        title: 'Server error', description: 'Contact support.');
    throw ServerError();
  } else if (data.statusCode == 200 || data.statusCode == 204) {
    return data;
  } else {
    throw UnexpectedResponse(data.statusCode);
  }
}

class ErrorInterceptor implements InterceptorContract {
  @override
  Future<RequestData> interceptRequest({required RequestData data}) async {
    return data;
  }

  @override
  Future<ResponseData> interceptResponse({required ResponseData data}) async {
    return await check_response(data, (x) {
      return jsonDecode(x.body!);
    });
  }
}

Future<String?> get_jwt_token_from_prefs() async {
  final prefs = await SharedPreferences.getInstance();
  final jwt = prefs.getString('jwt');
  return jwt;
}

class AuthInterceptor implements InterceptorContract {
  @override
  Future<RequestData> interceptRequest({required RequestData data}) async {
    final jwt = await get_jwt_token_from_prefs();
    if (jwt != null) {
      data.headers[HttpHeaders.cookieHeader] = jwt;
    }
    return data;
  }

  @override
  Future<ResponseData> interceptResponse({required ResponseData data}) async {
    String? jwt_cookie = data.headers?[HttpHeaders.setCookieHeader];
    if (jwt_cookie != null) {
      int index = jwt_cookie.indexOf(';');
      String jwt = jwt_cookie.substring(0, index);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt', jwt);
    }
    return data;
  }
}

class InvalidUsage {
  final status;
  final message;
  final code;

  InvalidUsage(
      {required this.status, required this.message, required this.code});
}

class ServerError {}

class UnexpectedResponse {
  final status;
  UnexpectedResponse(this.status);
}

class HttpService {
  final String baseurl = Environment().config.apiUrl;

  late http.Client client;

  HttpService() {
    client = InterceptedClient.build(
        interceptors: [ErrorInterceptor(), if (!kIsWeb) AuthInterceptor()],
        client: inner_client);
  }

  Future signout() async {
    final resp = await client.post(Uri.parse(baseurl + '/users/signout'));
  }

  Future fetch_me() async {
    final resp = await client.get(Uri.parse(baseurl + '/users/me'));
    final body = jsonDecode(resp.body);
    if (body['authenticated']) {
      _websocketService.reconnect();
    }
    return body;
  }

  Future signup(username) async {
    final resp = await client.post(Uri.parse(baseurl + '/users/signup'),
        body: jsonEncode({'username': username}));
    final body = jsonDecode(resp.body);
    if (body['authenticated']) {
      _websocketService.reconnect();
    }
    return body;
  }

  Future signin({username, password, email, token, method}) async {
    final resp = await client.post(Uri.parse(baseurl + '/users/signin'),
        body: jsonEncode({
          'username': username,
          'password': password,
          'email': email,
          'token': token,
          'method': method
        }));
    final body = jsonDecode(resp.body);
    if (body['authenticated']) {
      _websocketService.reconnect();
    }
    return body;
  }

  Future update_profile(data) async {
    final resp = await client.post(Uri.parse(baseurl + '/users/update-profile'),
        body: jsonEncode(data));
    final body = jsonDecode(resp.body);
    return body;
  }

  Future upload_profile_picture(data) async {
//    var stream = http.ByteStream(data);
//    stream.cast();
//    final length = await data.length();
    final request = http.MultipartRequest(
        'POST', Uri.parse(baseurl + '/users/upload-profile-picture'));
    if (!kIsWeb) {
      final jwt = await get_jwt_token_from_prefs();
      if (jwt != null) {
        request.headers[HttpHeaders.cookieHeader] = jwt;
      }
    }
    final multipart_file = http.MultipartFile.fromBytes('file', data);
    request.files.add(multipart_file);
    final resp = await client.send(request);
    final bodyfunc = (x) async {
      return jsonDecode(await x.stream.bytesToString());
    };
    final checked_resp = await check_response(resp, bodyfunc);
    return bodyfunc(resp);
  }

  Future checkin(lat, lon) async {
    final data = {'lat': lat, 'lon': lon};
    final resp = await client.post(Uri.parse(baseurl + '/social/checkin'),
        body: jsonEncode(data));
    final body = jsonDecode(resp.body);
    return body;
  }

  Future join_user(user_id) async {
    final data = {'user_id': user_id};
    final resp = await client.post(Uri.parse(baseurl + '/social/join-user'),
        body: jsonEncode(data));
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
    final resp = await client.post(Uri.parse(baseurl + '/social/get-messages'),
        body: jsonEncode(data));
    final body = jsonDecode(resp.body);
    return body;
  }

  Future send_message(room_id, message_body) async {
    final data = {'room_id': room_id, 'body': message_body};
    final resp = await client.post(Uri.parse(baseurl + '/social/send-message'),
        body: jsonEncode(data));
    final body = jsonDecode(resp.body);
    return body;
  }
}
