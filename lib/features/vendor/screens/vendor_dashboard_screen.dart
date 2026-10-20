import '../../../core/widgets/offer_photo.dart';
import '../../../core/images/image_selection_service.dart';
import '../../../core/images/offer_draft_store.dart';
import '../../../core/images/selected_image.dart';
import '../../../core/constants/offer_categories.dart';
import 'create_offer_screen.dart';

import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/errors/app_failure.dart';
import '../../../models/offer_model.dart';
import '../../auth/services/auth_service.dart';
import '../services/offer_service.dart';
import '../widgets/metric_card.dart';

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});
  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  late Stream<List<OfferModel>> _offers;
  SelectedImage? _recovered;
  Map<String, dynamic>? _draft;
  String? _recoveryError;
  @override
  void initState() {
    super.initState();
    _subscribe();
    _recover();
  }

  Future<void> _recover() async {
    final uid = AuthService.instance.identity!.uid;
    try {
      final draft = await OfferDraftStore.instance.read(uid);
      final pickerOwner = await OfferDraftStore.instance.pickerOwner();
      // Never consume another account's pending Android picker result.
      final image = pickerOwner == uid
          ? await ImageSelectionService.instance.recover()
          : null;
      if (pickerOwner == uid) await OfferDraftStore.instance.clearPicker();
      AuthService.instance.requireAccount(uid);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _recovered = image;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _recoveryError =
              'Draft/photo recovery failed: ${errorMessage(e)}',
        );
      }
    }
  }

  Future<void> _resumeDraft() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            CreateOfferScreen(recoveredImage: _recovered, draft: _draft),
      ),
    );
    if (mounted) {
      setState(() {
        _recovered = null;
        _draft = null;
      });
      await _recover();
    }
  }

  void _subscribe() {
    _offers = OfferService.instance.watchVendorOffers(
      AuthService.instance.identity!.uid,
    );
  }

  Future<void> _logout() async {
    try {
      await AuthService.instance.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthService.instance,
    builder: (context, _) {
      final user = AuthService.instance.profile;
      if (user == null) return const SizedBox.shrink();
      final approved = user.isApprovedVendor;
      final label = user.isPendingVendor
          ? 'APPROVAL PENDING'
          : approved
          ? 'APPROVED'
          : 'APPROVAL REVOKED / REJECTED';
      return Scaffold(
        appBar: AppBar(
          title: Text(user.displayName),
          actions: [
            IconButton(
              tooltip: 'Business profile',
              icon: const Icon(Icons.person_outline),
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.vendorProfile),
            ),
            IconButton(
              tooltip: 'Sign Out',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: approved
              ? () async {
                  await _recover();
                  if (!mounted) return;
                  if (_draft != null || _recovered != null) {
                    await _resumeDraft();
                  } else {
                    if (!context.mounted) return;
                    await Navigator.pushNamed(context, AppRoutes.createOffer);
                    if (mounted) await _recover();
                  }
                }
              : null,
          icon: const Icon(Icons.add),
          label: Text(approved ? 'Post Clearance Offer' : 'Approval required'),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: approved ? Colors.green.shade50 : Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (!approved)
                      const Text(
                        'Only approved vendors can publish. Changes to your approval appear automatically.',
                      ),
                  ],
                ),
              ),
            ),
            if (_recoveryError != null)
              Text(
                _recoveryError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_recovered != null || _draft != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton(
                  onPressed: _resumeDraft,
                  child: Text(
                    _recovered != null
                        ? 'Recover selected photo and draft'
                        : 'Resume unsaved offer',
                  ),
                ),
              ),
            Expanded(
              child: StreamBuilder<List<OfferModel>>(
                stream: _offers,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(errorMessage(snapshot.error!)),
                          ),
                          FilledButton(
                            onPressed: () => setState(_subscribe),
                            child: const Text('Retry offers'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final vendorOffers = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              title: 'Saved offers',
                              value: '${vendorOffers.length}',
                              icon: Icons.local_offer,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: 'Active offers',
                              value:
                                  '${vendorOffers.where((o) => o.status == 'active' && o.expiryTime.isAfter(DateTime.now())).length}',
                              icon: Icons.check_circle_outline,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Your offers',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (vendorOffers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No saved offers yet.'),
                        ),
                      ...vendorOffers.map(
                        (offer) => Card(
                          child: ListTile(
                            leading: offer.imageUrl.isEmpty
                                ? null
                                : OfferPhoto(url: offer.imageUrl),
                            title: Text(offer.title),
                            subtitle: Text(
                              '${offer.status} • ${OfferCategories.label(offer.category)} • ₹${offer.newPrice.toStringAsFixed(2)}',
                            ),
                            trailing: const Icon(Icons.cloud_done_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 90),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
