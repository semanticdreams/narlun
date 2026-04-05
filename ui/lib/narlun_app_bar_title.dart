import 'package:flutter/material.dart';

import 'narlun_wordmark.dart';

class NarlunAppBarTitle extends StatelessWidget {
  final String title;

  const NarlunAppBarTitle({super.key, this.title = 'narlun'});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/icon.png', width: 28, height: 28),
        const SizedBox(width: 10),
        if (title == 'narlun')
          const NarlunWordmark(size: 28)
        else
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
      ],
    );
  }
}
