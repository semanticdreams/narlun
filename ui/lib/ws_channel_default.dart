import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWsChannel(Uri uri, {Map<String, dynamic>? headers}) {
  return IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: const Duration(seconds: 5),
  );
}

Uri createWebSocketUri(
  String apiBaseUrl, {
  String? clientId,
  String? clientSessionId,
}) {
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
    queryParameters: _wsQueryParameters(
      clientId: clientId,
      clientSessionId: clientSessionId,
    ),
  );
}

Map<String, String>? _wsQueryParameters({
  String? clientId,
  String? clientSessionId,
}) {
  final params = <String, String>{};
  if (clientId != null && clientId.isNotEmpty) {
    params['client_id'] = clientId;
  }
  if (clientSessionId != null && clientSessionId.isNotEmpty) {
    params['client_session_id'] = clientSessionId;
  }
  return params.isEmpty ? null : params;
}
