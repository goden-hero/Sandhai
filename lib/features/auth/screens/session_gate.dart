import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../../../data/account_repository.dart';
import '../../customer/screens/customer_home_screen.dart';
import '../../onboarding/screens/welcome_screen.dart';
import '../../vendor/screens/vendor_dashboard_screen.dart';
import '../services/auth_service.dart';

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthService.instance,
    builder: (context, _) {
      final auth = AuthService.instance;
      return switch (auth.phase) {
        SessionPhase.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        SessionPhase.signedOut => const WelcomeScreen(),
        SessionPhase.error => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(errorMessage(auth.sessionError!)),
                  FilledButton(
                    onPressed: auth.retrySession,
                    child: const Text('Retry session'),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await auth.signOut();
                      } catch (e) {
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(errorMessage(e))),
                          );
                      }
                    },
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          ),
        ),
        SessionPhase.incomplete => CompletionScreen(
          key: ValueKey(auth.identity!.uid),
        ),
        SessionPhase.ready =>
          auth.profile!.isVendor
              ? const VendorDashboardScreen()
              : const CustomerHomeScreen(),
      };
    },
  );
}

class SessionGuard extends StatelessWidget {
  const SessionGuard({super.key, required this.child, this.vendorOnly = false});
  final Widget child;
  final bool vendorOnly;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthService.instance,
    builder: (context, _) {
      final auth = AuthService.instance;
      if (auth.phase != SessionPhase.ready ||
          (vendorOnly && !auth.profile!.isVendor))
        return const SessionGate();
      return child;
    },
  );
}

class CompletionScreen extends StatefulWidget {
  const CompletionScreen({super.key});
  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _address = TextEditingController();
  String _role = 'vendor';
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final profile = AuthService.instance.profile;
    _role = profile?.role ?? 'vendor';
    _name.text = profile?.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.instance.completeRegistration(
        RegistrationData(
          name: _name.text,
          role: AuthService.instance.profile?.role ?? _role,
          phone: _phone.text,
          address: _address.text,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Complete registration'),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  try {
                    await AuthService.instance.signOut();
                  } catch (e) {
                    if (mounted) setState(() => _error = errorMessage(e));
                  }
                },
          child: const Text('Sign Out'),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Signed in as ${AuthService.instance.identity!.email}. Complete your profile to continue.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (AuthService.instance.profile == null)
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Account type'),
                items: const [
                  DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                  DropdownMenuItem(value: 'customer', child: Text('Customer')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _role = v!),
              ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name / store name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter a name.' : null,
            ),
            if (_role == 'vendor') ...[
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Store phone'),
                validator: (v) =>
                    (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                    ? 'Enter a 10-digit phone number.'
                    : null,
              ),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Business address',
                ),
              ),
              const Text(
                'Vendor accounts require approval before offers can be published.',
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving… waiting for server confirmation'
                    : 'Complete registration',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
