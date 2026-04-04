import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:narlun/browser_picker_flow.dart';

void main() {
  test('returns null shortly after focus returns without a file selection', () async {
    final changeController = StreamController<void>();
    final focusController = StreamController<void>();

    final future = awaitBrowserPickerResult<String>(
      changeEvents: changeController.stream,
      focusEvents: focusController.stream,
      readSelection: () async => 'unused',
      cancelDelay: const Duration(milliseconds: 10),
      timeout: const Duration(seconds: 1),
    );

    focusController.add(null);
    await expectLater(future, completion(isNull));

    await changeController.close();
    await focusController.close();
  });

  test('returns the selected value when a change event arrives', () async {
    final changeController = StreamController<void>();
    final focusController = StreamController<void>();

    final future = awaitBrowserPickerResult<String>(
      changeEvents: changeController.stream,
      focusEvents: focusController.stream,
      readSelection: () async => 'picked-file',
      cancelDelay: const Duration(milliseconds: 10),
      timeout: const Duration(seconds: 1),
    );

    changeController.add(null);
    await expectLater(future, completion('picked-file'));

    await changeController.close();
    await focusController.close();
  });
}
