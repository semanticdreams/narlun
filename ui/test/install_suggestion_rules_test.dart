import 'package:flutter_test/flutter_test.dart';
import 'package:narlun/install_suggestion_rules.dart';

void main() {
  test('matches Safari on iPhone', () {
    final suggestion = resolveInstallSuggestion(
      userAgent:
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1',
      isInstalled: false,
      dismissed: false,
      isSecureContext: true,
      serviceWorkerSupported: true,
    );

    expect(suggestion?.message, 'In Safari, tap Share, then Add to Home Screen.');
  });

  test('matches Chrome on Android', () {
    final suggestion = resolveInstallSuggestion(
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36',
      isInstalled: false,
      dismissed: false,
      isSecureContext: true,
      serviceWorkerSupported: true,
    );

    expect(
      suggestion?.message,
      'Open the browser menu, then choose Install app or Add to Home screen.',
    );
  });

  test('matches Firefox on Android', () {
    final suggestion = resolveInstallSuggestion(
      userAgent:
          'Mozilla/5.0 (Android 14; Mobile; rv:137.0) Gecko/137.0 Firefox/137.0',
      isInstalled: false,
      dismissed: false,
      isSecureContext: true,
      serviceWorkerSupported: true,
    );

    expect(
      suggestion?.message,
      'Open the browser menu, tap More if it appears, then Add app to home screen.',
    );
  });

  test('stays hidden for unsupported or dismissed environments', () {
    expect(
      resolveInstallSuggestion(
        userAgent:
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Firefox/137.0',
        isInstalled: false,
        dismissed: false,
        isSecureContext: true,
        serviceWorkerSupported: true,
      ),
      isNull,
    );
    expect(
      resolveInstallSuggestion(
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36',
        isInstalled: false,
        dismissed: true,
        isSecureContext: true,
        serviceWorkerSupported: true,
      ),
      isNull,
    );
  });
}
