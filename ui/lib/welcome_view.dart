import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';

class WelcomeView extends StatefulWidget {
  @override
  _WelcomeState createState() => _WelcomeState();
}

class _WelcomeState extends State<WelcomeView> {
  final HttpService httpService = HttpService();

  Future<void> init_me() async {
    final me = await httpService.fetch_me();
    Provider.of<MeModel>(context, listen: false).set_data(me);
    if (ModalRoute.of(context)?.isCurrent == true) {
      final name = ModalRoute.of(context)!.settings.name;
      final uri_data = Uri.parse(name!);
      final next = uri_data.queryParameters['next'];

      Navigator.of(context).popUntil((route) => route.isFirst);

      if (next != null) {
        Navigator.pushReplacementNamed(context, next);
      } else {
        if (me['authenticated']) {
          Navigator.pushReplacementNamed(context, '/rooms');
        } else {
          Navigator.pushReplacementNamed(context, '/signup');
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    init_me();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4E2D72),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Image(
              image: AssetImage('assets/icon.png'),
              width: 96,
              height: 96,
            ),
            SizedBox(height: 20),
            Text(
              'Narlun',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 50,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Live nearby chat',
              style: TextStyle(color: Color(0xFFEADDF8)),
            ),
            SizedBox(height: 30),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
