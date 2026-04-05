import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';
import 'route_utils.dart';
import 'session_actions.dart';

class InviteAcceptView extends StatefulWidget {
  final String token;

  const InviteAcceptView({super.key, required this.token});

  @override
  State<InviteAcceptView> createState() => _InviteAcceptViewState();
}

class _InviteAcceptViewState extends State<InviteAcceptView> {
  late final HttpService _httpService;
  String? _error;
  bool _accepting = true;

  @override
  void initState() {
    super.initState();
    _httpService = Provider.of<HttpService>(context, listen: false);
    unawaited(_acceptInvite());
  }

  Future<void> _acceptInvite() async {
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      final room = await _httpService.accept_invite(widget.token);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushNamedAndRemoveUntil(
        roomsRouteWithOpenRoom(room.id),
        (route) => false,
      );
    } on UnauthorizedResponse {
      if (!mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: _httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } on InvalidUsage catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _accepting = false;
        _error = error.message as String?;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _accepting = false;
        _error = describeActionError(
          error,
          fallbackDescription: 'Could not open this invite right now.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<MeModel>(context).data;
    final title = _accepting ? 'Joining room...' : 'Invite unavailable';
    final body = _accepting
        ? const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Opening your invite...'),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'This invite could not be opened.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _acceptInvite,
                child: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    currentUser?.authenticated == true ? '/home' : '/signup',
                    (route) => false,
                  );
                },
                child: Text(
                  currentUser?.authenticated == true ? 'Back to home' : 'Sign up',
                ),
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Invite')),
      backgroundColor: const Color(0xFFF5ECFF),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    body,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
