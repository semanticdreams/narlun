import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWsChannel(Uri uri, {Map<String, dynamic>? headers}) {
  return WebSocketChannel.connect(uri);
}

Uri createWebSocketUri(String apiBaseUrl, {String? clientId}) {
  final apiBaseUri = Uri.parse(apiBaseUrl);
  if (apiBaseUri.hasScheme && apiBaseUri.host.isNotEmpty) {
    return Uri(
      scheme: apiBaseUri.scheme == 'https' ? 'wss' : 'ws',
      host: apiBaseUri.host,
      port: apiBaseUri.hasPort ? apiBaseUri.port : null,
      path: '/api/ws',
      queryParameters: clientId == null ? null : {'client_id': clientId},
    );
  }

  final pageUri = Uri.base;
  return Uri(
    scheme: pageUri.scheme == 'https' ? 'wss' : 'ws',
    host: pageUri.host,
    port: pageUri.hasPort ? pageUri.port : null,
    path: '/api/ws',
    queryParameters: clientId == null ? null : {'client_id': clientId},
  );
}
