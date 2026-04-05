import 'package:flutter/material.dart';

class NarlunWordmark extends StatelessWidget {
  const NarlunWordmark({
    super.key,
    this.size = 32,
    this.color = const Color(0xFF5F4484),
    this.textAlign,
  });

  final double size;
  final Color color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final shadowColor = Color.lerp(color, Colors.black, 0.45) ?? Colors.black;
    return Text(
      'narlun',
      textAlign: textAlign,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.3,
        height: 0.9,
        fontFamilyFallback: const [
          'Arial Rounded MT Bold',
          'Trebuchet MS',
          'Verdana',
        ],
        shadows: [
          Shadow(
            color: shadowColor.withValues(alpha: 0.24),
            offset: Offset(0, size * 0.035),
            blurRadius: size * 0.05,
          ),
          Shadow(
            color: shadowColor.withValues(alpha: 0.22),
            offset: Offset(size * 0.03, size * 0.1),
            blurRadius: size * 0.22,
          ),
        ],
      ),
    );
  }
}
