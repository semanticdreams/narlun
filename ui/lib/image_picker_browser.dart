// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

import 'browser_picker_flow.dart';

const _maxUploadBytes = 2 * 1024 * 1024;
const _maxUploadPixels = 20 * 1000 * 1000;
const _initialJpegQuality = 0.85;
const _minimumJpegQuality = 0.55;
const _jpegQualityStep = 0.1;
const _resizeStep = 0.85;
const _minimumUploadDimension = 256;

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
    final sourcePixels = sourceWidth * sourceHeight;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw StateError('Could not read the selected image.');
    }

    if (rawBytes.length <= _maxUploadBytes && sourcePixels <= _maxUploadPixels) {
      return rawBytes;
    }

    final preserveAlpha = _mimeTypeMayContainAlpha(mimeType);
    final pixelScale = sourcePixels > _maxUploadPixels
        ? math.sqrt(_maxUploadPixels / sourcePixels)
        : 1.0;
    var targetWidth = math.max(1, (sourceWidth * pixelScale).round());
    var targetHeight = math.max(1, (sourceHeight * pixelScale).round());
    Uint8List? bestBytes;

    while (true) {
      final candidate = await _encodePreparedImage(
        image,
        width: targetWidth,
        height: targetHeight,
        preserveAlpha: preserveAlpha,
      );
      if (candidate != null &&
          (bestBytes == null || candidate.length < bestBytes.length)) {
        bestBytes = candidate;
      }
      if (candidate != null && candidate.length <= _maxUploadBytes) {
        return candidate;
      }

      if (targetWidth <= _minimumUploadDimension ||
          targetHeight <= _minimumUploadDimension) {
        break;
      }

      final nextWidth = math.max(
        _minimumUploadDimension,
        (targetWidth * _resizeStep).round(),
      );
      final nextHeight = math.max(
        _minimumUploadDimension,
        (targetHeight * _resizeStep).round(),
      );
      if (nextWidth == targetWidth && nextHeight == targetHeight) {
        break;
      }
      targetWidth = nextWidth;
      targetHeight = nextHeight;
    }

    if (bestBytes != null && bestBytes.length < rawBytes.length) {
      return bestBytes;
    }
    return rawBytes;
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
  required int width,
  required int height,
  required bool preserveAlpha,
}) async {
  final canvas = html.CanvasElement(width: width, height: height);
  final context = canvas.context2D;
  context
    ..imageSmoothingEnabled = true
    ..clearRect(0, 0, width.toDouble(), height.toDouble())
    ..drawImageScaled(image, 0, 0, width.toDouble(), height.toDouble());

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
    if (encoded.length <= _maxUploadBytes) {
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
