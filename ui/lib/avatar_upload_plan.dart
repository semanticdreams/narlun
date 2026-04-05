import 'dart:math' as math;

const avatarUploadServerMaxBytes = 2 * 1024 * 1024;
const avatarUploadMultipartOverheadBytes = 64 * 1024;
const avatarUploadTargetBytes =
    avatarUploadServerMaxBytes - avatarUploadMultipartOverheadBytes;
const avatarUploadMaxPixels = 20 * 1000 * 1000;
const avatarUploadTargetDimension = 1024;
const avatarUploadMinimumDimension = 256;
const _avatarUploadResizeStep = 0.8;

class AvatarUploadPlan {
  const AvatarUploadPlan({
    required this.cropLeft,
    required this.cropTop,
    required this.cropSize,
    required this.targetSize,
  });

  final int cropLeft;
  final int cropTop;
  final int cropSize;
  final int targetSize;
}

AvatarUploadPlan? createAvatarUploadPlan({
  required int sourceWidth,
  required int sourceHeight,
  required int rawBytes,
}) {
  final sourcePixels = sourceWidth * sourceHeight;
  final cropSize = math.min(sourceWidth, sourceHeight);
  final shouldKeepOriginal =
      rawBytes <= avatarUploadTargetBytes &&
      cropSize <= avatarUploadTargetDimension &&
      sourcePixels <= avatarUploadMaxPixels;
  if (shouldKeepOriginal) {
    return null;
  }

  return AvatarUploadPlan(
    cropLeft: (sourceWidth - cropSize) ~/ 2,
    cropTop: (sourceHeight - cropSize) ~/ 2,
    cropSize: cropSize,
    targetSize: math.min(cropSize, avatarUploadTargetDimension),
  );
}

AvatarUploadPlan? nextAvatarUploadPlan(AvatarUploadPlan plan) {
  if (plan.targetSize <= avatarUploadMinimumDimension) {
    return null;
  }
  final nextTargetSize = math.max(
    avatarUploadMinimumDimension,
    (plan.targetSize * _avatarUploadResizeStep).round(),
  );
  if (nextTargetSize == plan.targetSize) {
    return null;
  }
  return AvatarUploadPlan(
    cropLeft: plan.cropLeft,
    cropTop: plan.cropTop,
    cropSize: plan.cropSize,
    targetSize: nextTargetSize,
  );
}
