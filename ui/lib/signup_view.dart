import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:username_gen/username_gen.dart';

import 'dialog_service.dart';
import 'http.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'route_utils.dart';

class SignupView extends StatefulWidget {
  const SignupView({super.key});

  @override
  SignupViewState createState() {
    return SignupViewState();
  }
}

class SignupViewState extends State<SignupView> {
  final usernameController = TextEditingController();
  late final HttpService httpService;

  bool usernameReadOnly = false;

  void submit() async {
    try {
      final SessionUser me = await httpService.signup(usernameController.text);
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
        title: 'Could not sign up',
        error: error,
        fallbackDescription:
            'Your account could not be created right now. Try again.',
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5ECFF),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'narlun',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 50,
                    color: Color(0xFF5F4484),
                  ),
                ),
                const Text(
                  'Talk to people nearby.\n\nChoose a username to start instantly.',
                  textAlign: TextAlign.center,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      label: 'signup-username',
                      textField: true,
                      child: TextField(
                        key: const Key('signup-username-field'),
                        autofocus: true,
                        readOnly: usernameReadOnly,
                        onTap: () {
                          setState(() {
                            usernameReadOnly = false;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Username',
                          suffixIcon: IconButton(
                            key: const Key('signup-generate-username-button'),
                            icon: const Icon(Icons.casino_outlined),
                            tooltip: 'Generate random username',
                            onPressed: () {
                              setState(() {
                                usernameReadOnly = true;
                              });
                              usernameController.text = UsernameGen().generate();
                            },
                          ),
                        ),
                        controller: usernameController,
                        onSubmitted: (_) => submit(),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 20),
                      child: Semantics(
                        label: 'signup-submit',
                        button: true,
                        child: ElevatedButton(
                          key: const Key('signup-submit-button'),
                          onPressed: submit,
                          child: const Text('Sign Up'),
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Guest accounts disappear on sign out. Add a password in profile settings to keep the account.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  child: const Text('Already have an account? Sign in'),
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                      context,
                      authRouteWithNext(context, '/signin'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
