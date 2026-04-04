import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';
import 'models.dart';

class WelcomeView extends StatefulWidget {
  const WelcomeView({Key? key}) : super(key: key);

  @override
  State<WelcomeView> createState() => _WelcomeState();
}

class _WelcomeState extends State<WelcomeView> {
  late final HttpService httpService;
  Timer? _retryTimer;
  bool _loading = true;
  int _attempt = 0;
  String _statusMessage = 'Checking your session...';
  String? _detailMessage;

  Duration _retryDelayForAttempt(int attempt) {
    final cappedSeconds = attempt <= 0
        ? 1
        : (1 << (attempt - 1)).clamp(1, 16);
    return Duration(seconds: cappedSeconds);
  }

  String _describeBootstrapFailure(Object error) {
    if (error is ServerError) {
      return 'The server responded with an error. Retrying automatically.';
    }
    if (error is UnexpectedResponse) {
      return 'Startup failed with status ${error.status}. Retrying automatically.';
    }
    return 'The app cannot reach the server right now. Retrying automatically.';
  }

  Future<void> _navigateAfterBootstrap(SessionUser me) async {
    Provider.of<MeModel>(context, listen: false).setData(me);
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final routeName = ModalRoute.of(context)!.settings.name;
    final routeUri = Uri.parse(routeName!);
    final next = routeUri.queryParameters['next'];

    Navigator.of(context).popUntil((route) => route.isFirst);

    if (next != null) {
      Navigator.pushReplacementNamed(context, next);
      return;
    }

    if (me.authenticated) {
      Navigator.pushReplacementNamed(context, '/rooms');
    } else {
      Navigator.pushReplacementNamed(context, '/signup');
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _retryDelayForAttempt(_attempt);
    setState(() {
      _loading = false;
      _statusMessage = 'Connection issue. Retrying in ${delay.inSeconds}s...';
    });
    _retryTimer = Timer(delay, () {
      unawaited(_bootstrapMe(resetBackoff: false));
    });
  }

  Future<void> _bootstrapMe({required bool resetBackoff}) async {
    _retryTimer?.cancel();
    if (!mounted) {
      return;
    }

    if (resetBackoff) {
      _attempt = 0;
    }

    setState(() {
      _loading = true;
      _statusMessage = _attempt == 0
          ? 'Checking your session...'
          : 'Retrying connection...';
      _detailMessage = null;
    });

    try {
      final me = await httpService.fetch_me(silentErrors: true);
      if (!mounted) {
        return;
      }
      await _navigateAfterBootstrap(me);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _attempt += 1;
      setState(() {
        _detailMessage = _describeBootstrapFailure(error);
      });
      _scheduleRetry();
    }
  }

  @override
  void initState() {
    super.initState();
    httpService = Provider.of<HttpService>(context, listen: false);
    unawaited(_bootstrapMe(resetBackoff: true));
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4E2D72),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Image(
              image: AssetImage('assets/icon.png'),
              width: 96,
              height: 96,
            ),
            const SizedBox(height: 20),
            const Text(
              'Narlun',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Live nearby chat',
              style: TextStyle(color: Color(0xFFEADDF8)),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            if (_detailMessage != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _detailMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFEADDF8)),
                ),
              ),
            ],
            if (!_loading) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () {
                  unawaited(_bootstrapMe(resetBackoff: true));
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
                child: const Text('Retry now'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
