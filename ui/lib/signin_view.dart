import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dialog_service.dart';
import 'http.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'narlun_wordmark.dart';
import 'route_utils.dart';

class SigninView extends StatefulWidget {
  const SigninView({super.key});

  @override
  SigninState createState() {
    return SigninState();
  }
}

class SigninState extends State<SigninView> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  late final HttpService httpService;

  void submit() async {
    try {
      final SessionUser me = await httpService.signin(
        username: usernameController.text,
        password: passwordController.text,
      );
      if (!mounted) {
        return;
      }
      Provider.of<MeModel>(context, listen: false).setData(me);
      Navigator.of(context).pushNamedAndRemoveUntil(
        nextRouteFromContext(context) ?? '/home',
        (route) => false,
      );
    } on InvalidUsage {
      usernameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: usernameController.value.text.length,
      );
    } catch (error) {
      await showActionErrorDialog(
        locator<DialogService>(),
        title: 'Could not sign in',
        error: error,
        fallbackDescription:
            'Sign in failed right now. Check your connection and try again.',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    httpService = Provider.of<HttpService>(context, listen: false);
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
              const NarlunWordmark(
                size: 50,
                color: Color(0xFF5F4484),
                textAlign: TextAlign.center,
              ),
              const Text(
                'Sign in with your username and password.',
                textAlign: TextAlign.center,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          label: 'signin-username',
                          textField: true,
                          child: TextField(
                            key: const Key('signin-username-field'),
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                            ),
                            controller: usernameController,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                        Semantics(
                          label: 'signin-password',
                          textField: true,
                          child: TextField(
                            key: const Key('signin-password-field'),
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            controller: passwordController,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 20.0),
                    child: Semantics(
                      label: 'signin-submit',
                      button: true,
                      child: ElevatedButton(
                        key: const Key('signin-submit-button'),
                        onPressed: submit,
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
                  Navigator.pushReplacementNamed(
                    context,
                    authRouteWithNext(context, '/signup'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
