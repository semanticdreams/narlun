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
        backgroundColor: const Color(0xFFF5ECFF),
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
                  color: Color(0xFF5F4484),
                ),
              ),
              const Text(
                'Sign in with your username and password.',
                textAlign: TextAlign.center,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: 'signin-username',
                    textField: true,
                    child: TextField(
                      key: const Key('signin-username-field'),
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Username'),
                      controller: usernameController,
                      onSubmitted: (_) => submit(context),
                    ),
                  ),
                  Semantics(
                    label: 'signin-password',
                    textField: true,
                    child: TextField(
                      key: const Key('signin-password-field'),
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      controller: passwordController,
                      onSubmitted: (_) => submit(context),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 20.0),
                    child: Semantics(
                      label: 'signin-submit',
                      button: true,
                      child: ElevatedButton(
                        key: const Key('signin-submit-button'),
                        onPressed: () => submit(context),
                        child: const Text('Sign In'),
                      ),
                    ),
                  ),
                ],
              ),
              const Text('', textAlign: TextAlign.center),
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
