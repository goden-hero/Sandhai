import '../../../core/location/store_location_editor.dart';

import 'package:flutter/material.dart';

import '../../../core/constants/offer_categories.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/operation_error.dart';
import '../../../models/vendor_model.dart';
import '../../auth/services/auth_service.dart';

class VendorProfileScreen extends StatefulWidget {
  const VendorProfileScreen({super.key});
  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(),
      _phoneController = TextEditingController(),
      _addressController = TextEditingController(),
      _descriptionController = TextEditingController();
  String _category = 'groceries';
  bool _isLoading = true, _isEditing = false, _isSaving = false, _dirty = false;
  String? _error;
  VendorModel? _vendor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _populate(VendorModel vendor) {
    _nameController.text = vendor.name;
    _phoneController.text = vendor.phone;
    _addressController.text = vendor.address ?? '';
    _descriptionController.text = vendor.description ?? '';
    _category = OfferCategories.normalize(vendor.category);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final vendor = await AuthService.instance.fetchVendorProfile(
        AuthService.instance.identity!.uid,
      );
      if (!mounted) return;
      if (vendor == null) {
        throw const AppFailure(
          'Your store profile is incomplete. Finish registration first.',
        );
      }
      _vendor = vendor;
      _populate(vendor);
    } catch (e) {
      if (mounted) _error = errorMessage(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfileUpdates() async {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final saved = await AuthService.instance.updateVendorProfile(
        uid: AuthService.instance.identity!.uid,
        name: _nameController.text,
        phone: _phoneController.text,
        category: _category,
        address: _addressController.text,
        description: _descriptionController.text,
      );
      if (!mounted) return;
      setState(() {
        _vendor = saved;
        _isEditing = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Vendor profile saved.')));
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(e));
        showOperationError(context, _error!);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _back(bool didPop, Object? result) async {
    if (didPop || _isSaving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('Discard your unsaved profile edits?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard Changes'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthService.instance,
    builder: (context, _) {
      final user = AuthService.instance.profile;
      if (user == null) return const SizedBox.shrink();
      final vendor = _isEditing
          ? _vendor
          : AuthService.instance.vendorProfile ?? _vendor;
      return PopScope(
        canPop: !_dirty && !_isSaving,
        onPopInvokedWithResult: _back,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Vendor Profile'),
            actions: [
              if (!_isEditing && !_isLoading && _error == null)
                IconButton(
                  tooltip: 'Edit Profile',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () {
                    _populate(vendor!);
                    setState(() => _isEditing = true);
                  },
                ),
              IconButton(
                tooltip: 'Sign Out',
                icon: const Icon(Icons.logout),
                onPressed: _isSaving
                    ? null
                    : () async {
                        try {
                          await AuthService.instance.signOut();
                        } catch (e) {
                          if (mounted) setState(() => _error = errorMessage(e));
                        }
                      },
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        user.isPendingVendor
                            ? 'APPROVAL PENDING'
                            : user.isApprovedVendor
                            ? 'VERIFIED STORE'
                            : 'REJECTED / SUSPENDED',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(user.email),
                      const SizedBox(height: 16),
                      if (vendor != null && !_isEditing) ...[
                        Text(
                          vendor.hasConfirmedLocation
                              ? 'Confirmed store: ${vendor.latitude}, ${vendor.longitude}'
                              : 'Store location needs confirmation before publishing.',
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  final saved = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const StoreLocationEditor(),
                                    ),
                                  );
                                  if (saved == true) await _load();
                                },
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('Confirm / edit store location'),
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      if (_vendor == null)
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry profile'),
                        ),
                      if (_isEditing)
                        Form(
                          key: _formKey,
                          onChanged: () => setState(() => _dirty = true),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                enabled: !_isSaving,
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Store name',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Business name is required.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _category,
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                ),
                                items: OfferCategories.values
                                    .where((c) => c != 'All')
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(OfferCategories.label(c)),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isSaving
                                    ? null
                                    : (v) => setState(() {
                                        _category = v!;
                                        _dirty = true;
                                      }),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                enabled: !_isSaving,
                                controller: _phoneController,
                                decoration: const InputDecoration(
                                  labelText: 'Phone',
                                ),
                                validator: (v) =>
                                    (v ?? '')
                                            .replaceAll(RegExp(r'\D'), '')
                                            .length <
                                        10
                                    ? 'Enter a 10-digit phone number.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                enabled: !_isSaving,
                                controller: _addressController,
                                decoration: const InputDecoration(
                                  labelText: 'Business address',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                enabled: !_isSaving,
                                controller: _descriptionController,
                                decoration: const InputDecoration(
                                  labelText: 'Description',
                                ),
                                maxLines: 3,
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _isSaving
                                    ? null
                                    : _saveProfileUpdates,
                                child: Text(
                                  _isSaving
                                      ? 'Saving… waiting for server confirmation'
                                      : 'Save profile',
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!_isEditing && vendor != null) ...[
                        Text(vendor.name, style: const TextStyle(fontSize: 24)),
                        Text(vendor.phone),
                        Text(OfferCategories.label(vendor.category)),
                        Text(vendor.address ?? ''),
                        Text(vendor.description ?? ''),
                      ],
                    ],
                  ),
                ),
        ),
      );
    },
  );
}
