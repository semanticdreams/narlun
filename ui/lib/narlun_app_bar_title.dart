import 'package:flutter/material.dart';

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
        Text(title),
      ],
    );
  }
}
