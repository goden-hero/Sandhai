import 'package:flutter/material.dart';
import '../../../app/router.dart';
import '../../../mock_data/mock_data.dart';
import '../../../models/offer_model.dart';
import '../../../models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../widgets/metric_card.dart';

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  final Map<String, dynamic> _metrics = MockData.getVendorDashboardMetrics();
  late List<OfferModel> _vendorOffers;
  late UserModel _currentVendorUser;

  @override
  void initState() {
    super.initState();
    _currentVendorUser = AuthService.instance.demoCurrentUser ??
        UserModel(
          uid: MockData.sampleVendor.uid,
          displayName: MockData.sampleVendor.name,
          email: 'vendor@greenvalley.com',
          role: 'vendor',
          approvalStatus: 'pending', // Default registered vendor starts as PENDING
          createdAt: DateTime.now(),
        );

    _refreshOffers();
  }

  void _refreshOffers() {
    final posted = OfferService.instance.demoOffers.where((o) => o.vendorId == _currentVendorUser.uid || o.vendorId == MockData.sampleVendor.uid);
    final mock = MockData.getMockOffers().where((o) => o.vendorId == MockData.sampleVendor.uid);
    _vendorOffers = [...posted, ...mock];
  }

  @override
  Widget build(BuildContext context) {
    final isPending = _currentVendorUser.isPendingVendor;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAlignment: CrossAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentVendorUser.displayName.isNotEmpty
                      ? _currentVendorUser.displayName
                      : _metrics['storeName'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.orange.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPending ? 'PENDING' : 'APPROVED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isPending ? Colors.orange.shade900 : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '📍 ${_metrics['location']} (Mock Location)',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile & Settings',
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.profile, arguments: 'vendor');
            },
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAlignment: CrossAlignment.start,
          children: [
            // Vendor Onboarding / Pending Approval Notice Banner
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
                            'Store Registration Pending Approval',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.amber.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your vendor account is under review by 5KM Sandhai team. Offer creation is guarded until store verification.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Prominent Create Offer Action Button (Guarded for Pending Vendors)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (isPending) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ Store Approval Required: Pending vendors cannot publish offers.'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  Navigator.pushNamed(context, AppRoutes.createOffer);
                },
                icon: Icon(isPending ? Icons.lock_outline : Icons.add_circle_outline, size: 22),
                label: Text(isPending ? 'Post Offer (Approval Pending)' : 'Post New Clearance Offer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPending ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Summary Metrics Title with Mock Disclaimer
            Row(
              children: [
                const Text(
                  'Dashboard Overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Mock Data',
                    style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2x2 Grid of Metrics
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: [
                MetricCard(
                  title: 'Active Offers',
                  value: '${_vendorOffers.length}',
                  icon: Icons.local_offer,
                  color: Theme.of(context).colorScheme.primary,
                ),
                MetricCard(
                  title: 'Views Today',
                  value: '${_metrics['viewsToday']}',
                  icon: Icons.visibility,
                  color: Colors.blue.shade700,
                ),
                MetricCard(
                  title: 'Customer Calls',
                  value: '${_metrics['customerEnquiries']}',
                  icon: Icons.phone_callback,
                  color: Colors.green.shade700,
                ),
                MetricCard(
                  title: 'Alert Radius',
                  value: '${_metrics['coverageRadiusKm']} KM',
                  icon: Icons.radar,
                  color: Colors.purple.shade700,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section Header: Active Offers
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Clearance Offers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.createOffer);
                  },
                  child: const Text('+ Add Offer'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Vendor Active Offers List
            if (_vendorOffers.isEmpty)
              _buildEmptyVendorState()
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _vendorOffers.length,
                itemBuilder: (context, index) {
                  final offer = _vendorOffers[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        offer.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            Text(
                              '₹${offer.newPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '₹${offer.oldPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                offer.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Offer editing will be implemented in Task 5.'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: Theme.of(context).colorScheme.secondary,
        onTap: (index) {
          if (index == 1) {
            Navigator.pushNamed(context, AppRoutes.createOffer);
          } else if (index == 2) {
            Navigator.pushNamed(context, AppRoutes.profile, arguments: 'vendor');
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box),
            label: 'New Offer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyVendorState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.inbox, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('No active clearance offers posted.'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.createOffer),
              child: const Text('Post First Offer'),
            ),
          ],
        ),
      ),
    );
  }
}
