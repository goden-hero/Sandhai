import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/offer_categories.dart';
import '../../../models/user_model.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/operation_error.dart';
import '../../auth/services/auth_service.dart';
import '../services/offer_service.dart';

class CreateOfferScreen extends StatefulWidget {
  const CreateOfferScreen({super.key});

  @override
  State<CreateOfferScreen> createState() => _CreateOfferScreenState();
}

class _CreateOfferScreenState extends State<CreateOfferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _oldPriceController = TextEditingController();
  final _newPriceController = TextEditingController();
  String _selectedCategory = 'Groceries';
  String _selectedDuration = '6 Hours';

  bool _isSubmitting = false;
  String? _errorMessage;

  // Selected image state
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _hasSelectedImage = false;

  UserModel get _currentVendorUser => AuthService.instance.profile!;
  late final String _offerId;
  String _progress = 'Saving… waiting for server confirmation';
  @override
  void initState() {
    super.initState();
    _offerId = OfferService.instance.newOfferId();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _oldPriceController.dispose();
    _newPriceController.dispose();
    super.dispose();
  }

  int _parseDurationHours(String duration) {
    switch (duration) {
      case '2 Hours':
        return 2;
      case '4 Hours':
        return 4;
      case '6 Hours':
        return 6;
      case '12 Hours':
        return 12;
      case '24 Hours':
        return 24;
      default:
        return 6;
    }
  }

  void _pickSampleImage() {
    if (!AuthService.instance.isDemo) return;
    setState(() {
      _selectedImageBytes = Uint8List.fromList(
        List.generate(1024, (i) => i % 256),
      );
      _selectedImageName =
          'clearance_item_${DateTime.now().millisecondsSinceEpoch}.jpg';
      _hasSelectedImage = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📷 Offer image attached successfully!'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _removeSelectedImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
      _hasSelectedImage = false;
    });
  }

  Future<void> _handlePublishOffer() async {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).clearSnackBars();

    if (_currentVendorUser.isPendingVendor ||
        _currentVendorUser.isRejectedVendor) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _currentVendorUser.isPendingVendor
                ? '⚠️ Store Approval Pending: You cannot publish offers until store verification.'
                : '🛑 Account Suspended: Offer publishing is disabled.',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final oldPrice = double.parse(_oldPriceController.text.trim());
      final newPrice = double.parse(_newPriceController.text.trim());
      final durationHours = _parseDurationHours(_selectedDuration);

      await OfferService.instance.createOffer(
        offerId: _offerId,
        onProgress: (message) {
          if (mounted) setState(() => _progress = message);
        },
        title: _titleController.text,
        description: _descController.text,
        oldPrice: oldPrice,
        newPrice: newPrice,
        category: _selectedCategory,
        durationHours: durationHours,
        imageBytes: _selectedImageBytes,
        imageFileName: _selectedImageName,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Clearance offer published successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.vendorDashboard,
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = errorMessage(e);
          _isSubmitting = false;
        });
        showOperationError(context, _errorMessage!);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthService.instance,
    builder: (context, _) => _buildForm(context),
  );
  Widget _buildForm(BuildContext context) {
    final availableCategories = OfferCategories.values
        .where((c) => c != 'All')
        .toList();
    final isPending = _currentVendorUser.isPendingVendor;
    final isApproved = _currentVendorUser.isApprovedVendor;

    return Scaffold(
      appBar: AppBar(title: const Text('Post Clearance Offer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pending or Rejected Vendor Guard Banner
              if (!isApproved) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.amber.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPending
                          ? Colors.amber.shade300
                          : Colors.red.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPending ? Icons.hourglass_top_outlined : Icons.block,
                        color: isPending
                            ? Colors.amber.shade900
                            : Colors.red.shade900,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPending
                                  ? 'Store Approval Required'
                                  : 'Account Suspended',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isPending
                                    ? Colors.amber.shade900
                                    : Colors.red.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isPending
                                  ? 'Your vendor account status is PENDING. Offer creation is guarded until 5KM Sandhai store verification.'
                                  : 'Offer publishing is disabled for suspended or rejected vendor accounts.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isPending
                                    ? Colors.amber.shade900
                                    : Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Error Banner
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade900,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Offer Title Field
              const Text(
                'Offer Title *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                enabled: !_isSubmitting,
                controller: _titleController,
                maxLength: 100,
                decoration: const InputDecoration(
                  hintText: 'e.g., Organic Alphonso Mangoes 1kg',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an offer title.';
                  }
                  if (value.trim().length > 100) {
                    return 'Title cannot exceed 100 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Description Field
              const Text(
                'Offer Description *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                enabled: !_isSubmitting,
                controller: _descController,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText: 'e.g., Surplus clearance stock. Fresh and ready to consume.',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a product description.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Category Selector Dropdown
              const Text(
                'Category *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: availableCategories.contains(_selectedCategory)
                    ? _selectedCategory
                    : availableCategories.first,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.category),
                ),
                items: availableCategories
                    .map(
                      (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 16),

              // Price Row (Original vs Clearance Price)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Original Price (₹) *',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          enabled: !_isSubmitting,
                          controller: _oldPriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(hintText: '160'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter price.';
                            }
                            final val = double.tryParse(value.trim());
                            if (val == null || val <= 0) {
                              return 'Must be > 0';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Clearance Price (₹) *',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          enabled: !_isSubmitting,
                          controller: _newPriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(hintText: '70'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter price.';
                            }
                            final newP = double.tryParse(value.trim());
                            if (newP == null || newP <= 0) {
                              return 'Must be > 0';
                            }
                            final oldP = double.tryParse(
                              _oldPriceController.text.trim(),
                            );
                            if (oldP != null && newP > oldP) {
                              return 'Must be <= ₹$oldP';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Expiry Duration Selector
              const Text(
                'Offer Validity / Expiry *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedDuration,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.timer),
                ),
                items: ['2 Hours', '4 Hours', '6 Hours', '12 Hours', '24 Hours']
                    .map(
                      (dur) => DropdownMenuItem(value: dur, child: Text(dur)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDuration = val);
                },
              ),
              const SizedBox(height: 16),

              if (_isSubmitting)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_progress),
                ),
              if (!AuthService.instance.isDemo)
                const Text(
                  'Image selection will be added in a later phase. Offers can be saved without an image.',
                ),
              // Image Selection & Attachment Box
              const Text(
                'Offer Image (Optional / Max 5MB)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              if (_hasSelectedImage) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.image,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedImageName ?? 'clearance_item.jpg',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'JPG Image Attached (Ready to Upload)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.blue),
                        tooltip: 'Replace Image',
                        onPressed: AuthService.instance.isDemo
                            ? _pickSampleImage
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        tooltip: 'Remove Image',
                        onPressed: _removeSelectedImage,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                InkWell(
                  onTap: AuthService.instance.isDemo ? _pickSampleImage : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 110,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.shade400,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 36,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to attach product image',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Submit Action Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (!isApproved || _isSubmitting)
                      ? null
                      : _handlePublishOffer,
                  icon: Icon(
                    !isApproved ? Icons.lock : Icons.cloud_upload_outlined,
                  ),
                  label: Text(
                    !isApproved
                        ? 'Publish Locked (Store Approval Pending)'
                        : 'Publish Clearance Offer',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isApproved
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
