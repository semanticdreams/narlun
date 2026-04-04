// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'browser_picker_flow.dart';

Future<Uint8List?> pickImageBytes() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false
    ..style.position = 'fixed'
    ..style.left = '-9999px'
    ..style.opacity = '0';
  html.document.body?.append(input);

  Future<Uint8List?> readSelection() async {
    final file = input.files?.first;
    if (file == null) {
      return null;
    }

    final reader = html.FileReader();
    final completer = Completer<Uint8List?>();
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      if (!completer.isCompleted) {
        completer.complete(result is Uint8List ? result : null);
      }
    });
    reader.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });
    reader.readAsArrayBuffer(file);
    return completer.future;
  }

  try {
    input.click();
    return await awaitBrowserPickerResult(
      changeEvents: input.onChange.map((_) {}),
      focusEvents: html.window.onFocus.map((_) {}),
      readSelection: readSelection,
    );
  } finally {
    input.remove();
  }
}
