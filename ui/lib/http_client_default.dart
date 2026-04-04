import 'package:http/http.dart' as http;

String? _sessionCookie;

http.Client createHttpClient() {
  return _SessionCookieClient(http.Client());
}

Future<String?> readSessionCookie() async => _sessionCookie;

Future<void> clearSessionCookie() async {
  _sessionCookie = null;
}

class _SessionCookieClient extends http.BaseClient {
  _SessionCookieClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_sessionCookie != null && !request.headers.containsKey('Cookie')) {
      request.headers['Cookie'] = _sessionCookie!;
    }

    final response = await _inner.send(request);
    _updateSessionCookie(response.headers['set-cookie']);
    return response;
  }

  void _updateSessionCookie(String? setCookieHeader) {
    if (setCookieHeader == null || setCookieHeader.isEmpty) {
      return;
    }

    final cookie = setCookieHeader.split(';').first.trim();
    if (cookie == 'jwt=' || cookie == 'jwt=""') {
      _sessionCookie = null;
      return;
    }

    if (cookie.startsWith('jwt=')) {
      _sessionCookie = cookie;
    }
  }
}
