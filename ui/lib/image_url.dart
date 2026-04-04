import 'config.dart';

const defaultAvatarUrl = 'http://www.gravatar.com/avatar/?d=mp';

String resolveImageUrl(String? value) {
  if (value == null || value.isEmpty) {
    return defaultAvatarUrl;
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }

  final baseUri = Uri.parse(Environment().config.apiUrl);
  return '${baseUri.origin}$value';
}
