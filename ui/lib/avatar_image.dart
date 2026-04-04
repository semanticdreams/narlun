import 'package:flutter/material.dart';

import 'image_url.dart';

class AvatarImage extends StatelessWidget {
  final String? picture;
  final double radius;

  const AvatarImage({Key? key, required this.picture, this.radius = 20})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: Image.network(
          resolveImageUrl(picture),
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return SizedBox(width: diameter, height: diameter);
          },
        ),
      ),
    );
  }
}
