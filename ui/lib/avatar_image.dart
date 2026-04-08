import 'package:flutter/material.dart';

import 'image_url.dart';

class AvatarImage extends StatelessWidget {
  final String? picture;
  final double radius;

  const AvatarImage({super.key, required this.picture, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final imageUrl = resolveImageUrl(picture);

    if (imageUrl.isEmpty) {
      return _FallbackAvatar(radius: radius);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: Image.network(
          imageUrl,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _FallbackAvatar(radius: radius);
          },
        ),
      ),
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  const _FallbackAvatar({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE7D9F6),
      child: Icon(
        Icons.person_rounded,
        size: radius,
        color: const Color(0xFF5F4484),
      ),
    );
  }
}
