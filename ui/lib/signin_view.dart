import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';


class SigninView extends StatefulWidget {
  const SigninView({Key? key}) : super(key: key);

  @override
  SigninState createState() {
    return SigninState();
  }
}


class SigninState extends State<SigninView> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final HttpService httpService = HttpService();

  void submit(BuildContext context) async {
    try {
      final me = await httpService.signin(
        username: usernameController.text,
        password: passwordController.text,
      );
      Provider.of<MeModel>(context, listen: false).set_data(me);
      Navigator.pushNamed(context, '/rooms');
    } on InvalidUsage {
      usernameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: usernameController.value.text.length,
      );
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: Scaffold(
        backgroundColor: Colors.purple[100],
        body: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Narlun',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 50,
                  color: Colors.purple,
                ),
              ),
              const Text(
                'Sign in with your username and password.',
                textAlign: TextAlign.center,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Username'),
                    controller: usernameController,
                    onSubmitted: (_) => submit(context),
                  ),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    controller: passwordController,
                    onSubmitted: (_) => submit(context),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 20.0),
                    child: ElevatedButton(
                      onPressed: () => submit(context),
                      child: Text(
                        'Sign In',
                        style: TextStyle(color: Colors.purple[100]),
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                '',
                textAlign: TextAlign.center,
              ),
              TextButton(
                child: const Text('Don\'t have an account? Click to sign up.'),
                onPressed: () {
                  Navigator.pushNamed(context, '/signup');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
