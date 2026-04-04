import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWsChannel(Uri uri, {Map<String, dynamic>? headers}) {
  return IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: const Duration(seconds: 5),
  );
}

Uri createWebSocketUri(String apiBaseUrl) {
  final apiBaseUri = Uri.parse(apiBaseUrl);
  if (!apiBaseUri.hasScheme || apiBaseUri.host.isEmpty) {
    throw StateError(
      'A fully qualified API URL is required outside the browser runtime.',
    );
  }

  return Uri(
    scheme: apiBaseUri.scheme == 'https' ? 'wss' : 'ws',
    host: apiBaseUri.host,
    port: apiBaseUri.hasPort ? apiBaseUri.port : null,
    path: '/api/ws',
  );
}
