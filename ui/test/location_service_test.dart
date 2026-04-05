import 'package:flutter_test/flutter_test.dart';

import 'package:narlun/location_service.dart';

void main() {
  test('createLocationService returns a shared singleton instance', () {
    final first = createLocationService();
    final second = createLocationService();

    expect(identical(first, second), isTrue);
  });
}
