import 'dart:typed_data';

import 'image_picker_default.dart'
    if (dart.library.html) 'image_picker_browser.dart'
    as impl;

Future<Uint8List?> pickImageBytes() => impl.pickImageBytes();
