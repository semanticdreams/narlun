const whatsappGroupHost = 'chat.whatsapp.com';
const whatsappGroupPreviewLabel = 'Join WhatsApp group';

String? normalizeWhatsappGroupInviteUrl(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final candidate =
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null) {
    return null;
  }
  if (uri.host.toLowerCase() != whatsappGroupHost) {
    return null;
  }
  final nonEmptySegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (nonEmptySegments.length != 1) {
    return null;
  }
  return Uri(
    scheme: 'https',
    host: whatsappGroupHost,
    pathSegments: nonEmptySegments,
  ).toString();
}
