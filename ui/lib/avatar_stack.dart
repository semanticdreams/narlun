import 'package:flutter/material.dart';

import 'avatar_image.dart';

class AvatarStack extends StatelessWidget {
  final List<String?> pictures;
  final int totalCount;
  final double avatarRadius;

  const AvatarStack({
    super.key,
    required this.pictures,
    required this.totalCount,
    this.avatarRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final visiblePictures = pictures.take(3).toList();
    final visibleCount = visiblePictures.length;
    final overlap = avatarRadius * 1.15;
    final extraCount = totalCount - visibleCount;
    final width = visibleCount <= 1
        ? avatarRadius * 2
        : (avatarRadius * 2) + ((visibleCount - 1) * overlap);

    return SizedBox(
      width: extraCount > 0 ? width + 24 : width,
      height: avatarRadius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visiblePictures.length; i++)
            Positioned(
              left: i * overlap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).canvasColor, width: 2),
                ),
                child: AvatarImage(
                  picture: visiblePictures[i],
                  radius: avatarRadius,
                ),
              ),
            ),
          if (extraCount > 0)
            Positioned(
              left: width + 4,
              top: 0,
              child: CircleAvatar(
                radius: avatarRadius - 1,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  '+$extraCount',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
