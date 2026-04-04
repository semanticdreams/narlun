import 'package:flutter_test/flutter_test.dart';

import 'package:narlun/passphrase_generator.dart';

void main() {
  test('generatePassphrase returns the requested number of words', () {
    var next = 0;
    final passphrase = generatePassphrase(
      pickIndex: (maxExclusive) {
        final value = next % maxExclusive;
        next += 1;
        return value;
      },
    );

    final words = passphrase.split(' ');
    expect(words, hasLength(defaultPassphraseWordCount));
    expect(words.every((word) => RegExp(r'^[a-z]+$').hasMatch(word)), isTrue);
  });
}
