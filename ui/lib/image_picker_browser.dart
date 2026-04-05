// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'avatar_upload_plan.dart';
import 'browser_picker_flow.dart';

const _initialJpegQuality = 0.85;
const _minimumJpegQuality = 0.35;
const _jpegQualityStep = 0.1;

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
    final bytes = await completer.future;
    if (bytes == null) {
      return null;
    }
    return _prepareImageForUpload(file, bytes);
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

Future<Uint8List> _prepareImageForUpload(
  html.File file,
  Uint8List rawBytes,
) async {
  final mimeType = file.type.toLowerCase();
  if (!mimeType.startsWith('image/')) {
    return rawBytes;
  }

  final objectUrl = html.Url.createObjectUrl(file);
  final image = html.ImageElement();
  final loadCompleter = Completer<void>();

  image.onLoad.first.then((_) {
    if (!loadCompleter.isCompleted) {
      loadCompleter.complete();
    }
  });
  image.onError.first.then((_) {
    if (!loadCompleter.isCompleted) {
      loadCompleter.completeError(
        StateError('Could not read the selected image.'),
      );
    }
  });
  image.src = objectUrl;

  try {
    await loadCompleter.future;
    final sourceWidth = image.naturalWidth;
    final sourceHeight = image.naturalHeight;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw StateError('Could not read the selected image.');
    }

    final plan = createAvatarUploadPlan(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      rawBytes: rawBytes.length,
    );
    if (plan == null) {
      return rawBytes;
    }

    final preserveAlpha = _mimeTypeMayContainAlpha(mimeType);
    Uint8List? bestBytes;
    AvatarUploadPlan? currentPlan = plan;

    while (currentPlan != null) {
      final candidate = await _encodePreparedImage(
        image,
        cropLeft: currentPlan.cropLeft,
        cropTop: currentPlan.cropTop,
        cropSize: currentPlan.cropSize,
        targetSize: currentPlan.targetSize,
        preserveAlpha: preserveAlpha,
      );
      if (candidate != null &&
          (bestBytes == null || candidate.length < bestBytes.length)) {
        bestBytes = candidate;
      }
      if (candidate != null && candidate.length <= avatarUploadTargetBytes) {
        return candidate;
      }
      currentPlan = nextAvatarUploadPlan(currentPlan);
    }

    if (bestBytes != null && bestBytes.length <= avatarUploadTargetBytes) {
      return bestBytes;
    }
    throw StateError('Could not prepare the selected picture for upload.');
  } finally {
    html.Url.revokeObjectUrl(objectUrl);
  }
}

bool _mimeTypeMayContainAlpha(String mimeType) {
  return mimeType == 'image/png' ||
      mimeType == 'image/webp' ||
      mimeType == 'image/gif';
}

Future<Uint8List?> _encodePreparedImage(
  html.ImageElement image, {
  required int cropLeft,
  required int cropTop,
  required int cropSize,
  required int targetSize,
  required bool preserveAlpha,
}) async {
  final canvas = html.CanvasElement(width: targetSize, height: targetSize);
  final context = canvas.context2D;
  context
    ..imageSmoothingEnabled = true
    ..clearRect(0, 0, targetSize.toDouble(), targetSize.toDouble())
    ..drawImageScaledFromSource(
      image,
      cropLeft,
      cropTop,
      cropSize,
      cropSize,
      0,
      0,
      targetSize,
      targetSize,
    );

  if (preserveAlpha) {
    final blob = await canvas.toBlob('image/png');
    return _readBlobBytes(blob);
  }

  Uint8List? bestBytes;
  for (var quality = _initialJpegQuality;
      quality >= _minimumJpegQuality;
      quality -= _jpegQualityStep) {
    final blob = await canvas.toBlob('image/jpeg', quality);
    final encoded = await _readBlobBytes(blob);
    if (encoded == null) {
      continue;
    }
    if (bestBytes == null || encoded.length < bestBytes.length) {
      bestBytes = encoded;
    }
    if (encoded.length <= avatarUploadTargetBytes) {
      return encoded;
    }
  }
  return bestBytes;
}

Future<Uint8List?> _readBlobBytes(html.Blob blob) async {
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
  reader.readAsArrayBuffer(blob);
  return completer.future;
}
