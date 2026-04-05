import 'package:flutter_test/flutter_test.dart';

import 'package:narlun/avatar_upload_plan.dart';

void main() {
  test('small avatar image can be uploaded unchanged', () {
    final plan = createAvatarUploadPlan(
      sourceWidth: 800,
      sourceHeight: 800,
      rawBytes: 240 * 1024,
    );

    expect(plan, isNull);
  });

  test('large camera photo is cropped and scaled for avatar upload', () {
    final plan = createAvatarUploadPlan(
      sourceWidth: 4032,
      sourceHeight: 3024,
      rawBytes: 4 * 1024 * 1024,
    );

    expect(plan, isNotNull);
    expect(plan!.cropLeft, 504);
    expect(plan.cropTop, 0);
    expect(plan.cropSize, 3024);
    expect(plan.targetSize, avatarUploadTargetDimension);
  });

  test('oversized image dimensions still trigger preprocessing', () {
    final plan = createAvatarUploadPlan(
      sourceWidth: 6000,
      sourceHeight: 4000,
      rawBytes: 300 * 1024,
    );

    expect(plan, isNotNull);
    expect(plan!.targetSize, avatarUploadTargetDimension);
  });

  test('avatar upload plan shrinks down to the minimum dimension', () {
    var plan = const AvatarUploadPlan(
      cropLeft: 0,
      cropTop: 0,
      cropSize: 3024,
      targetSize: avatarUploadTargetDimension,
    );

    while (true) {
      final next = nextAvatarUploadPlan(plan);
      if (next == null) {
        break;
      }
      expect(next.targetSize, lessThan(plan.targetSize));
      expect(next.targetSize, greaterThanOrEqualTo(avatarUploadMinimumDimension));
      plan = next;
    }

    expect(plan.targetSize, avatarUploadMinimumDimension);
    expect(nextAvatarUploadPlan(plan), isNull);
  });
}
