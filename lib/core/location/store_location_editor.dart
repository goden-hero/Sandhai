import 'package:flutter/material.dart';

import '../errors/app_failure.dart';
import '../widgets/operation_error.dart';
import '../../features/auth/services/auth_service.dart';
import 'location_service.dart';
import 'store_location.dart';

class StoreLocationEditor extends StatefulWidget {
  const StoreLocationEditor({super.key});
  @override
  State<StoreLocationEditor> createState() => _StoreLocationEditorState();
}

class _StoreLocationEditorState extends State<StoreLocationEditor> {
  final _form = GlobalKey<FormState>();
  final _lat = TextEditingController(), _lng = TextEditingController();
  bool _busy = false, _confirmed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final store = AuthService.instance.vendorProfile;
    // Do not prefill unconfirmed legacy/sample coordinates as a suggestion.
    if (store?.hasConfirmedLocation == true) {
      _lat.text = store!.latitude.toString();
      _lng.text = store.longitude.toString();
    }
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final suggestion = await LocationService.instance.suggest();
      if (!mounted) return;
      setState(() {
        _lat.text = suggestion.latitude.toString();
        _lng.text = suggestion.longitude.toString();
        _confirmed = false;
      });
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    setState(() => _error = errorMessage(e));
    showOperationError(context, _error!);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_confirmed) {
      _showError(
        const AppFailure('Confirm that these coordinates identify your store.'),
      );
      return;
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.confirmStoreLocation(
        StoreLocation(
          double.parse(_lat.text.trim()),
          double.parse(_lng.text.trim()),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(String? s, double limit) {
    final n = double.tryParse(s?.trim() ?? '');
    return n == null || !n.isFinite || n < -limit || n > limit
        ? 'Enter a number between -$limit and $limit.'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Confirm store location')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Use device location as a suggestion, then check or correct the coordinates. Only confirm the location of your store. These coordinates are public on published offers.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _suggest,
              icon: const Icon(Icons.my_location),
              label: const Text('Suggest device location'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        final opened = await LocationService.instance
                            .openSettings();
                        if (!opened) {
                          _showError(
                            const AppFailure(
                              'Open your browser site permissions or device location settings, then retry.',
                            ),
                          );
                        }
                      } catch (e) {
                        _showError(e);
                      }
                    },
              child: const Text('Location permission settings'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextFormField(
              controller: _lat,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Store latitude'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (v) => _validate(v, 90),
              onChanged: (_) => setState(() => _confirmed = false),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lng,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Store longitude'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (v) => _validate(v, 180),
              onChanged: (_) => setState(() => _confirmed = false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: _busy ? null : (v) => setState(() => _confirmed = v!),
              title: const Text('I confirm this is my store location'),
            ),
            if (_busy) const Text('Working… waiting for confirmation'),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save confirmed location'),
            ),
          ],
        ),
      ),
    ),
  );
}
