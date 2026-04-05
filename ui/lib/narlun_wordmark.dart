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
        fontStyle: FontStyle.italic,
        letterSpacing: -0.9,
        height: 0.96,
        fontFamilyFallback: const [
          'Trebuchet MS',
          'Arial Rounded MT Bold',
          'Verdana',
        ],
        shadows: [
          Shadow(
            color: shadowColor.withValues(alpha: 0.24),
            offset: Offset(size * 0.035, size * 0.08),
            blurRadius: size * 0.2,
          ),
        ],
      ),
    );
  }
}
