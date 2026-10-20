import '../../../core/images/offer_draft_store.dart';
import '../../../core/images/image_selection_service.dart';
import '../../../core/images/selected_image.dart';
import '../../../core/location/store_location_editor.dart';

import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/offer_categories.dart';
import '../../../models/user_model.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/operation_error.dart';
import '../../auth/services/auth_service.dart';
import '../services/offer_service.dart';

class CreateOfferScreen extends StatefulWidget {
  const CreateOfferScreen({super.key, this.recoveredImage, this.draft});
  final SelectedImage? recoveredImage;
  final Map<String, dynamic>? draft;

  @override
  State<CreateOfferScreen> createState() => _CreateOfferScreenState();
}

class _CreateOfferScreenState extends State<CreateOfferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _oldPriceController = TextEditingController();
  final _newPriceController = TextEditingController();
  String _selectedCategory = 'groceries';
  String _selectedDuration = '6 Hours';

  bool _isSubmitting = false;
  String? _errorMessage;

  SelectedImage? _image;
  bool _picking = false;

  UserModel get _currentVendorUser => AuthService.instance.profile!;
  late final String _offerId;
  String _progress = 'Saving… waiting for server confirmation';
  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _offerId = draft?['id'] as String? ?? OfferService.instance.newOfferId();
    if (draft != null) {
      _titleController.text = draft['title'] as String? ?? '';
      _descController.text = draft['description'] as String? ?? '';
      _oldPriceController.text = draft['oldPrice'] as String? ?? '';
      _newPriceController.text = draft['newPrice'] as String? ?? '';
      _selectedCategory = OfferCategories.normalize(draft['category']);
      _selectedDuration = draft['duration'] as String? ?? '6 Hours';
    }
    _image = widget.recoveredImage;
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

  Future<void> _retainDraft(String uid) => OfferDraftStore.instance.save(uid, {
    'id': _offerId,
    'title': _titleController.text,
    'description': _descController.text,
    'oldPrice': _oldPriceController.text,
    'newPrice': _newPriceController.text,
    'category': _selectedCategory,
    'duration': _selectedDuration,
  });

  Future<void> _pickImage() async {
    final uid = AuthService.instance.identity!.uid;
    setState(() {
      _picking = true;
      _errorMessage = null;
    });
    try {
      await _retainDraft(uid);
      await OfferDraftStore.instance.markPicker(uid);
      final selected = await ImageSelectionService.instance.pick();
      await OfferDraftStore.instance.clearPicker();
      AuthService.instance.requireAccount(uid);
      if (mounted && selected != null) setState(() => _image = selected);
      // Cancellation leaves the previous selection and form untouched.
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = errorMessage(e));
        showOperationError(context, _errorMessage!);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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

      final uid = AuthService.instance.identity!.uid;
      await _retainDraft(uid);
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
        imageBytes: _image?.bytes,
        imageFileName: _image?.filename,
      );

      // Publication is already confirmed; a local draft-removal failure must
      // not turn a confirmed server save into an apparent failure.
      try {
        await OfferDraftStore.instance.clear(uid);
      } catch (_) {
        /* A resumed same-ID draft reconciles to the saved offer. */
      }
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
                      (cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(OfferCategories.label(cat)),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() => _selectedCategory = val);
                        }
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
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() => _selectedDuration = val);
                        }
                      },
              ),
              const SizedBox(height: 16),

              if (_isSubmitting)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_progress),
                ),
              const Text(
                'Offer photo (optional): JPEG, PNG, or WebP; up to 5 MiB and 40 megapixels.',
              ),
              if (_image != null) ...[
                Image.memory(
                  _image!.bytes,
                  height: 180,
                  fit: BoxFit.contain,
                  semanticLabel: 'Selected offer photo preview',
                ),
                Text('${_image!.contentType} • ${_image!.bytes.length} bytes'),
                TextButton(
                  onPressed: _isSubmitting || _picking
                      ? null
                      : () => setState(() => _image = null),
                  child: const Text('Remove photo'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: _isSubmitting || _picking ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_picking ? 'Opening photos…' : 'Choose photo'),
              ),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 32),

              if (AuthService.instance.vendorProfile?.hasConfirmedLocation !=
                  true) ...[
                const Text('Confirm your store location before publishing.'),
                OutlinedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StoreLocationEditor(),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                  child: const Text('Confirm store location'),
                ),
              ],
              // Submit Action Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (!isApproved || _isSubmitting || _picking)
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
