import 'package:flutter/material.dart';
import '../../../app/router.dart';
import '../../../mock_data/mock_data.dart';
import '../../../models/user_model.dart';
import '../../../models/vendor_model.dart';
import '../../auth/services/auth_service.dart';

class VendorProfileScreen extends StatefulWidget {
  const VendorProfileScreen({super.key});

  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen> {
  bool _isEditing = false;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  late UserModel _userModel;
  VendorModel? _vendorModel;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _descriptionController;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _descriptionController = TextEditingController();
    _selectedCategory = 'Groceries';
    _loadVendorProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadVendorProfile() async {
    setState(() => _isLoading = true);

    _userModel = AuthService.instance.demoCurrentUser ??
        UserModel(
          uid: MockData.sampleVendor.uid,
          displayName: MockData.sampleVendor.name,
          email: 'vendor@greenvalley.com',
          role: 'vendor',
          approvalStatus: 'pending',
          createdAt: DateTime.now(),
        );

    final vendorDoc = await AuthService.instance.fetchVendorProfile(_userModel.uid);
    if (vendorDoc != null) {
      _vendorModel = vendorDoc;
    } else {
      // Fallback mock vendor object for display
      _vendorModel = VendorModel(
        uid: _userModel.uid,
        name: _userModel.displayName.isNotEmpty ? _userModel.displayName : MockData.sampleVendor.name,
        phone: MockData.sampleVendor.phone,
        category: MockData.sampleVendor.category,
        address: '42 Usman Road, T. Nagar, Chennai - 600017',
        description: 'Quality fresh produce and organic grocery clearance deals.',
        latitude: MockData.sampleVendor.latitude,
        longitude: MockData.sampleVendor.longitude,
        geohash: MockData.sampleVendor.geohash,
        createdAt: DateTime.now(),
      );
    }

    _populateControllers();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _populateControllers() {
    if (_vendorModel != null) {
      _nameController.text = _vendorModel!.name;
      _phoneController.text = _vendorModel!.phone;
      _addressController.text = _vendorModel!.address ?? '';
      _descriptionController.text = _vendorModel!.description ?? '';
      if (MockData.categories.contains(_vendorModel!.category)) {
        _selectedCategory = _vendorModel!.category;
      }
    }
  }

  Future<void> _saveProfileUpdates() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updated = await AuthService.instance.updateVendorProfile(
        uid: _userModel.uid,
        name: _nameController.text,
        phone: _phoneController.text,
        category: _selectedCategory,
        address: _addressController.text,
        description: _descriptionController.text,
      );

      if (!mounted) return;

      setState(() {
        _vendorModel = updated;
        _isEditing = false;
        _isSaving = false;
        _hasUnsavedChanges = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Vendor profile updated successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Failed to update profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved edits to your business profile. Are you sure you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Editing'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard Changes'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final availableCategories = MockData.categories.where((c) => c != 'All').toList();
    final isPending = _userModel.isPendingVendor;
    final isRejected = _userModel.isRejectedVendor;

    Color badgeColor = Colors.green.shade100;
    Color badgeTextColor = Colors.green.shade900;
    String badgeText = 'VERIFIED STORE';

    if (isPending) {
      badgeColor = Colors.amber.shade100;
      badgeTextColor = Colors.amber.shade900;
      badgeText = 'APPROVAL PENDING';
    } else if (isRejected) {
      badgeColor = Colors.red.shade100;
      badgeTextColor = Colors.red.shade900;
      badgeText = 'REJECTED / SUSPENDED';
    }

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final pop = await _onWillPop();
        if (pop) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Business Profile' : 'Vendor Profile'),
          actions: [
            if (!_isEditing && !_isLoading)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit Profile',
                onPressed: () => setState(() => _isEditing = true),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () async {
                await AuthService.instance.signOut();
                if (mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, AppRoutes.welcome, (route) => false);
                }
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAlignment: CrossAlignment.start,
                  children: [
                    // Header Banner: Store Name & Verification Badge
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 42,
                            backgroundColor: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                            child: Icon(
                              Icons.storefront,
                              size: 44,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _vendorModel?.name ?? _userModel.displayName,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userModel.email,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'VENDOR ROLE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: badgeTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Pending Approval Notice Banner
                    if (isPending) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_top_outlined, color: Colors.amber.shade900, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAlignment: CrossAlignment.start,
                                children: [
                                  Text(
                                    'Account Awaiting Verification',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'You may view and update your store details below. Clearance offer posting is restricted until store approval.',
                                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Rejected / Suspended Notice Banner
                    if (isRejected) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.block_outlined, color: Colors.red.shade900, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAlignment: CrossAlignment.start,
                                children: [
                                  Text(
                                    'Vendor Registration Suspended or Rejected',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Offer posting and active clearance operations are disabled. Please contact support for assistance.',
                                    style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Mode Switch: View vs Edit Mode
                    if (_isEditing)
                      Form(
                        key: _formKey,
                        onChanged: () => setState(() => _hasUnsavedChanges = true),
                        child: Column(
                          crossAlignment: CrossAlignment.start,
                          children: [
                            const Text('Edit Business Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 16),

                            // Store Name Input
                            const Text('Business Name *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.store)),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Business name is required.';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // Category Selector
                            const Text('Business Category *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: availableCategories.contains(_selectedCategory) ? _selectedCategory : availableCategories.first,
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.category)),
                              items: availableCategories
                                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedCategory = val);
                              },
                            ),
                            const SizedBox(height: 14),

                            // Phone Input
                            const Text('Contact Phone Number *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.phone)),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Phone number is required.';
                                final cleanDigits = val.replaceAll(RegExp(r'\D'), '');
                                if (cleanDigits.length < 10) return 'Valid 10-digit phone number required.';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // Address Input
                            const Text('Business Address *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.location_on)),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Address is required.';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // Description Input
                            const Text('Business Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Store clearance specialization...',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Action Buttons: Save & Cancel
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                            _populateControllers();
                                            setState(() {
                                              _isEditing = false;
                                              _hasUnsavedChanges = false;
                                            });
                                          },
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.secondary,
                                    ),
                                    onPressed: _isSaving ? null : _saveProfileUpdates,
                                    child: _isSaving
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Text('Save Changes'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      // View Mode
                      Column(
                        crossAlignment: CrossAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Store Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              TextButton.icon(
                                onPressed: () => setState(() => _isEditing = true),
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('Edit Profile'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Card(
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  _buildProfileRow(Icons.store, 'Store Name', _vendorModel?.name ?? 'N/A'),
                                  const Divider(),
                                  _buildProfileRow(Icons.category, 'Category', _vendorModel?.category ?? 'N/A'),
                                  const Divider(),
                                  _buildProfileRow(Icons.phone, 'Contact Phone', _vendorModel?.phone ?? 'N/A'),
                                  const Divider(),
                                  _buildProfileRow(Icons.location_on, 'Business Address', _vendorModel?.address ?? 'T. Nagar, Chennai'),
                                  const Divider(),
                                  _buildProfileRow(Icons.description, 'Description', _vendorModel?.description ?? 'No description provided.'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          const Text('Account System Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),

                          Card(
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  _buildProfileRow(Icons.fingerprint, 'Firebase UID', _userModel.uid),
                                  const Divider(),
                                  _buildProfileRow(Icons.email, 'Account Email', _userModel.email),
                                  const Divider(),
                                  _buildProfileRow(Icons.shield, 'Approval Status', _userModel.approvalStatus.toUpperCase()),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAlignment: CrossAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAlignment: CrossAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
