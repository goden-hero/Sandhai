import 'package:flutter/material.dart';

import '../../../app/config.dart';
import '../../../app/router.dart';
import '../../../core/constants/offer_categories.dart';
import '../../../core/location/location_service.dart';
import '../../../data/nearby_offer_repository.dart';
import '../../../data/nearby_query_source.dart';
import '../../../mock_data/mock_data.dart';
import '../../../models/offer_model.dart';
import '../../auth/services/auth_service.dart';
import '../nearby_feed_controller.dart';
import '../widgets/offer_card.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key, this.nearbyController});
  final NearbyFeedController? nearbyController;
  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen>
    with WidgetsBindingObserver {
  String _category = 'All', _query = '';
  bool _demoEmpty = false;
  bool _profileOpen = false;
  late final bool _demo;
  NearbyFeedController? _nearby;
  late List<OfferModel> _demoOffers;
  final _searchField = TextEditingController();

  @override
  void initState() {
    super.initState();
    _demo = AppConfig.current.isDemo;
    _demoOffers = _demo ? MockData.getMockOffers() : [];
    if (!_demo) {
      _nearby =
          widget.nearbyController ??
          NearbyFeedController(
            auth: AuthService.instance,
            repository: NearbyOfferRepository(
              source: FirebaseNearbyQuerySource(),
            ),
            location: LocationService.instance,
          );
      _nearby!.addListener(_changed);
    }
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _nearby?.recheckExpiry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nearby?.removeListener(_changed);
    if (widget.nearbyController == null) _nearby?.dispose();
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_demo) {
      setState(() => _demoOffers = MockData.getMockOffers());
    } else {
      await _nearby!.refresh();
    }
  }

  Future<void> _openProfile() async {
    if (_profileOpen) return;
    _profileOpen = true;
    try {
      await _nearby?.pause();
      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        AppRoutes.profile,
        arguments: 'customer',
      );
      if (mounted) await _nearby?.resume();
    } finally {
      _profileOpen = false;
    }
  }

  bool _matches(OfferModel offer) =>
      (_category == 'All' || offer.category == _category) &&
      (offer.title.toLowerCase().contains(_query.toLowerCase()) ||
          offer.description.toLowerCase().contains(_query.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final visible = _demo
        ? [
            if (!_demoEmpty)
              ..._demoOffers.where(_matches).map((o) => NearbyOffer(o, 1200)),
          ]
        : _nearby!.offers.where((v) => _matches(v.offer)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '5KM Sandhai',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _demo ? 'Demo offers • Mock 5 KM' : 'Nearby offers • Within 5 km',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (!_demo)
            IconButton(
              onPressed: _nearby!.phase == NearbyPhase.locating
                  ? null
                  : _nearby!.locate,
              icon: const Icon(Icons.my_location),
              tooltip: 'Update customer location',
            ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile & Settings',
            onPressed: _openProfile,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchField,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search clearance items near you...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: OfferCategories.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final id = OfferCategories.values[i];
                      return ChoiceChip(
                        label: Text(OfferCategories.label(id)),
                        labelStyle: TextStyle(
                          color: _category == id
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        selectedColor: Theme.of(context).colorScheme.primary,
                        checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                        selected: _category == id,
                        onSelected: (_) => setState(() => _category = id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_demo)
            SwitchListTile(
              title: const Text('Simulate Empty:'),
              value: _demoEmpty,
              onChanged: (v) => setState(() => _demoEmpty = v),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (!_demo && _nearby!.phase != NearbyPhase.ready)
                    _status()
                  else if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          const Icon(Icons.search_off, size: 54),
                          const SizedBox(height: 12),
                          const Text(
                            'No clearance offers found',
                            style: TextStyle(fontSize: 18),
                          ),
                          const Text(
                            'No matching active offers within 5 km. Try another category or refresh.',
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: () {
                              _searchField.clear();
                              setState(() {
                                _query = '';
                                _category = 'All';
                                _demoEmpty = false;
                              });
                            },
                            child: const Text('Reset Filters'),
                          ),
                          OutlinedButton(
                            onPressed: _refresh,
                            child: const Text('Refresh nearby offers'),
                          ),
                        ],
                      ),
                    )
                  else
                    ...visible.map(
                      (v) => OfferCard(
                        key: ValueKey(v.offer.id),
                        offer: v.offer,
                        distanceMetres: v.distanceMetres,
                        demo: _demo,
                      ),
                    ),
                  if (!_demo &&
                      _nearby!.phase == NearbyPhase.ready &&
                      visible.isNotEmpty)
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('Refresh nearby offers'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (i) {
          if (i == 1) {
            _openProfile();
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.local_offer),
            label: 'Deals',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _status() {
    final phase = _nearby!.phase;
    if (phase == NearbyPhase.loading || phase == NearbyPhase.locating) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              phase == NearbyPhase.locating
                  ? 'Finding your location…'
                  : 'Loading nearby offers…',
            ),
          ],
        ),
      );
    }
    final locationError = phase == NearbyPhase.locationError;
    final queryError = phase == NearbyPhase.queryError;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            queryError ? Icons.cloud_off : Icons.location_on_outlined,
            size: 54,
          ),
          Text(
            queryError
                ? 'Could not load nearby offers'
                : locationError
                ? 'Location unavailable'
                : 'Find offers near you',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 12),
          Text(
            _nearby!.error ?? 'Use your foreground location to find active clearance offers within 5 km.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: queryError ? _refresh : _nearby!.locate,
            child: Text(queryError ? 'Retry nearby offers' : 'Use my location'),
          ),
          if (locationError)
            TextButton(
              onPressed: () async {
                final opened = await _nearby!.location.openSettings();
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Allow location in browser/device settings, then retry.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Location settings'),
            ),
        ],
      ),
    );
  }
}
