class InstallSuggestion {
  const InstallSuggestion({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;
}

InstallSuggestion? resolveInstallSuggestion({
  required String? userAgent,
  required bool isInstalled,
  required bool dismissed,
  required bool isSecureContext,
  required bool serviceWorkerSupported,
}) {
  if (isInstalled || dismissed || !isSecureContext || !serviceWorkerSupported) {
    return null;
  }
  final normalizedUserAgent = (userAgent ?? '').toLowerCase();
  if (normalizedUserAgent.isEmpty) {
    return null;
  }
  if (_isIosSafari(normalizedUserAgent)) {
    return const InstallSuggestion(
      title: 'Install Narlun',
      message: 'In Safari, tap Share, then Add to Home Screen.',
    );
  }
  if (_isIosChrome(normalizedUserAgent)) {
    return const InstallSuggestion(
      title: 'Install Narlun',
      message: 'In Chrome, tap Share, then Add to Home Screen.',
    );
  }
  if (_isAndroidFirefox(normalizedUserAgent)) {
    return const InstallSuggestion(
      title: 'Install Narlun',
      message:
          'Open the browser menu, tap More if it appears, then Add app to home screen.',
    );
  }
  if (_isAndroidChromium(normalizedUserAgent)) {
    return const InstallSuggestion(
      title: 'Install Narlun',
      message:
          'Open the browser menu, then choose Install app or Add to Home screen.',
    );
  }
  return null;
}

bool _isIosSafari(String userAgent) {
  if (!_isIos(userAgent)) {
    return false;
  }
  return userAgent.contains('safari') &&
      !userAgent.contains('crios') &&
      !userAgent.contains('fxios') &&
      !userAgent.contains('edgios');
}

bool _isIosChrome(String userAgent) {
  return _isIos(userAgent) && userAgent.contains('crios');
}

bool _isAndroidFirefox(String userAgent) {
  return userAgent.contains('android') && userAgent.contains('firefox');
}

bool _isAndroidChromium(String userAgent) {
  if (!userAgent.contains('android')) {
    return false;
  }
  return userAgent.contains('chrome') ||
      userAgent.contains('edga') ||
      userAgent.contains('samsungbrowser') ||
      userAgent.contains('brave');
}

bool _isIos(String userAgent) {
  return userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod');
}
