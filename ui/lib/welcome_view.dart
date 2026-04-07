import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';
import 'models.dart';
import 'narlun_wordmark.dart';
import 'route_utils.dart';
import 'web_install_state.dart';

class WelcomeView extends StatefulWidget {
  const WelcomeView({
    super.key,
    this.isStandaloneContext = isStandaloneWebAppContext,
  });

  final bool Function() isStandaloneContext;

  @override
  State<WelcomeView> createState() => _WelcomeState();
}

class _WelcomeState extends State<WelcomeView> {
  late final HttpService httpService;
  Timer? _retryTimer;
  bool _loading = true;
  int _attempt = 0;
  String? _attemptedInstallSessionToken;
  String _statusMessage = 'Getting Narlun ready...';
  String? _detailMessage;

  Duration _retryDelayForAttempt(int attempt) {
    final cappedSeconds = attempt <= 0 ? 1 : (1 << (attempt - 1)).clamp(1, 16);
    return Duration(seconds: cappedSeconds);
  }

  String _describeBootstrapFailure(Object error) {
    if (error is ServerError) {
      return 'Narlun is having trouble starting right now. We will keep trying.';
    }
    if (error is UnexpectedResponse) {
      return 'Narlun hit a snag while opening. We will keep trying.';
    }
    return 'Narlun cannot connect right now. We will keep trying.';
  }

  Future<void> _navigateAfterBootstrap(SessionUser me) async {
    Provider.of<MeModel>(context, listen: false).setData(me);
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final routeName = ModalRoute.of(context)!.settings.name;
    final routeUri = Uri.parse(routeName!);
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.pushReplacementNamed(
      context,
      resolveStartupLocation(routeUri, me),
    );
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _retryDelayForAttempt(_attempt);
    setState(() {
      _loading = false;
      _statusMessage =
          'Still trying to connect. Trying again in ${delay.inSeconds}s...';
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
          ? 'Getting Narlun ready...'
          : 'Trying again...';
      _detailMessage = null;
    });

    try {
      final routeName = ModalRoute.of(context)?.settings.name;
      final routeUri = routeName == null ? null : Uri.parse(routeName);
      final installSessionToken = routeUri?.queryParameters['install_session'];
      if (widget.isStandaloneContext() &&
          installSessionToken != null &&
          installSessionToken.isNotEmpty &&
          _attemptedInstallSessionToken != installSessionToken) {
        _attemptedInstallSessionToken = installSessionToken;
        final claimedUser = await httpService.claimInstallSession(
          installSessionToken,
        );
        if (!mounted) {
          return;
        }
        if (claimedUser.authenticated) {
          await _navigateAfterBootstrap(claimedUser);
          return;
        }
      }

      final me = await httpService.fetch_me(
        silentErrors: true,
        reconnectWebsocket: false,
      );
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
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF291B3D), Color(0xFF1B1328)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: const Alignment(0, -1.15),
              child: Container(
                width: 520,
                height: 320,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x619870C9), Color(0x009870C9)],
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x14FFFFFF),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 60,
                              offset: Offset(0, 20),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 28,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Image(
                                image: AssetImage('assets/icon.png'),
                                width: 76,
                                height: 76,
                              ),
                              const SizedBox(height: 18),
                              const NarlunWordmark(
                                size: 32,
                                color: Color(0xFFF7EFFF),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Nearby chat is opening. This should only take a moment.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFD6C6EB),
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const SizedBox(
                                width: 56,
                                height: 56,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _statusMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFF7EFFF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_detailMessage != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _detailMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFD6C6EB),
                                    height: 1.5,
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
                                    side: const BorderSide(
                                      color: Color(0xB3FFFFFF),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text('Try again'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
