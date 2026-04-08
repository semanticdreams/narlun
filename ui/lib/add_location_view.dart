import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service.dart';
import 'models.dart';

class AddLocationView extends StatefulWidget {
  const AddLocationView({
    super.key,
    required this.locationService,
    required this.onAdd,
  });

  final LocationService locationService;
  final Future<bool> Function(LocationMessageData location) onAdd;

  @override
  State<AddLocationView> createState() => _AddLocationViewState();
}

class _AddLocationViewState extends State<AddLocationView> {
  Position? _position;
  String? _errorText;
  bool _isResolving = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveLocation());
  }

  Future<void> _resolveLocation() async {
    setState(() {
      _isResolving = true;
      _errorText = null;
    });
    try {
      if (!(await widget.locationService.isLocationServiceEnabled())) {
        throw StateError('Location services are not enabled.');
      }
      var permission = await widget.locationService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await widget.locationService.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('Location access was denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location access is permanently denied on this device.',
        );
      }
      final position = await widget.locationService.getCurrentPosition();
      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
        _isResolving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = null;
        _isResolving = false;
        _errorText = error is StateError
            ? error.message.toString()
            : 'Could not get your location right now.';
      });
    }
  }

  Future<void> _submit() async {
    final position = _position;
    if (position == null || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    try {
      final added = await widget.onAdd(
        LocationMessageData(
          lat: position.latitude,
          lon: position.longitude,
          accuracyMeters: position.accuracy.isFinite && position.accuracy >= 0
              ? position.accuracy
              : null,
        ),
      );
      if (added && mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildBody(BuildContext context) {
    if (_isResolving) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_disabled_rounded,
              size: 34,
              color: Color(0xFF7B5E49),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _errorText!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF2A3A35),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('location-retry-button'),
            onPressed: _resolveLocation,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      );
    }

    final location = LocationMessageData(
      lat: _position!.latitude,
      lon: _position!.longitude,
      accuracyMeters: _position!.accuracy.isFinite && _position!.accuracy >= 0
          ? _position!.accuracy
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Share your current location in this room.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF2A3A35),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFDE4CE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFD86F2C),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Current location',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF1F2528),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  location.coordinateLabel,
                  key: const Key('location-coordinate-label'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF33423D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (location.accuracyLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    location.accuracyLabel!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E6967),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('location-add-submit-button'),
            onPressed: _isSubmitting ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_isSubmitting ? 'Sending...' : 'Send location'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3E8DA),
        appBar: AppBar(
          title: const Text('Share location'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isSubmitting
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }
}
