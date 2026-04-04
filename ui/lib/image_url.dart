import 'config.dart';

String resolveImageUrl(String? value) {
  if (value == null || value.isEmpty) {
    return '';
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }

  final baseUri = Uri.parse(Environment().config.apiUrl);
  if (!baseUri.hasScheme) {
    return value;
  }
  return '${baseUri.origin}$value';
}
