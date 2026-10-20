import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../app/config.dart';
import '../../../core/constants/offer_categories.dart';
import '../../../mock_data/mock_data.dart';
import '../../../models/offer_model.dart';
import '../widgets/offer_card.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = false;
  bool _showEmptyState = false;
  List<OfferModel> _offers = [];

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  void _loadOffers() {
    setState(() {
      _offers = AppConfig.current.isDemo ? MockData.getMockOffers() : [];
    });
  }

  Future<void> _handleRefresh() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _offers = AppConfig.current.isDemo ? MockData.getMockOffers() : [];
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppConfig.current.isDemo
                ? 'Demo offers refreshed.'
                : 'Nearby discovery will be added in a later phase.',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  List<OfferModel> get _filteredOffers {
    if (_showEmptyState) return [];
    return _offers.where((offer) {
      // 1. Text Search Filter
      final matchesQuery =
          _searchQuery.isEmpty ||
          offer.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          offer.description.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesQuery) return false;

      // 2. Category Filter
      if (_selectedCategory == 'All') return true;

      return offer.category == _selectedCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '5KM Sandhai',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'CUSTOMER',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  AppConfig.current.isDemo
                      ? 'T. Nagar, Chennai (Mock 5 KM)'
                      : 'Nearby discovery is not connected yet',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile & Settings',
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.profile,
                arguments: 'customer',
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: Column(
          children: [
            // Search & Filter Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  // Search Bar UI
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search clearance items near you...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear Search',
                              onPressed: () =>
                                  setState(() => _searchQuery = ''),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Category Selector Chips
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: OfferCategories.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final cat = OfferCategories.values[index];
                        final isSelected = cat == _selectedCategory;
                        return ChoiceChip(
                          label: Text(OfferCategories.label(cat)),
                          selected: isSelected,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = cat),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Demo State Toggle Bar (allows testing Empty / Normal states)
            if (AppConfig.current.isDemo)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.orange.shade50,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_filteredOffers.length} Deals Nearby',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Text(
                      'Simulate Empty:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Switch(
                      value: _showEmptyState,
                      activeThumbColor: Theme.of(context).colorScheme.primary,
                      onChanged: (val) => setState(() => _showEmptyState = val),
                    ),
                  ],
                ),
              ),

            // Offers List / Loading / Empty State
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredOffers.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredOffers.length,
                      itemBuilder: (context, index) {
                        return OfferCard(offer: _filteredOffers[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: (index) {
          if (index == 1) {
            Navigator.pushNamed(
              context,
              AppRoutes.profile,
              arguments: 'customer',
            );
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No clearance offers found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Try changing your search query or selecting a different category.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => setState(() {
                _showEmptyState = false;
                _searchQuery = '';
                _selectedCategory = 'All';
              }),
              child: const Text('Reset Filters'),
            ),
          ],
        ),
      ),
    );
  }
}
