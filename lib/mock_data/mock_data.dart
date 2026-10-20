import '../core/utils/geohash_utils.dart';
import '../models/offer_model.dart';
import '../models/vendor_model.dart';

/// Centralized repository of temporary mock data for 5KM Sandhai UI Demo.
/// All data here is marked explicitly as mock data and will be replaced by
/// Cloud Firestore queries in subsequent tasks.
class MockData {
  static final VendorModel sampleVendor = VendorModel(
    uid: 'vendor_demo_01',
    name: 'Green Valley Organics',
    phone: '+91 98765 43210',
    category: 'Fresh Produce & Groceries',
    latitude: 13.0402,
    longitude: 80.2337,
    geohash: GeohashUtils.encode(13.0402, 80.2337),
    createdAt: DateTime.now().subtract(const Duration(days: 30)),
  );

  static final List<String> categories = [
    'All',
    'Groceries',
    'Fresh Produce',
    'Bakery & Dairy',
    'Snacks & Beverages',
    'Services',
  ];

  static List<OfferModel> getMockOffers() {
    final now = DateTime.now();
    return [
      OfferModel(
        id: 'offer_1',
        vendorId: 'vendor_demo_01',
        title: 'Organic Alphonso Mangoes 1kg',
        category: 'fresh_produce',
        description: 'Ripe Alphonso mangoes, surplus clearance stock. Best eaten within 24 hours!',
        oldPrice: 160.0,
        newPrice: 70.0,
        imageUrl: '', // Local icon fallback
        latitude: 13.0402,
        longitude: 80.2337,
        geohash: GeohashUtils.encode(13.0402, 80.2337),
        createdAt: now.subtract(const Duration(minutes: 45)),
        expiryTime: now.add(const Duration(hours: 3)),
        status: 'active',
      ),
      OfferModel(
        id: 'offer_2',
        vendorId: 'vendor_demo_02',
        title: 'Fresh Whole Wheat Bread (2 Loaves)',
        category: 'groceries',
        description:
            'Freshly baked today at 6 AM. Clearance before bakery closing.',
        oldPrice: 90.0,
        newPrice: 40.0,
        imageUrl: '',
        latitude: 13.0380,
        longitude: 80.2300,
        geohash: GeohashUtils.encode(13.0380, 80.2300),
        createdAt: now.subtract(const Duration(hours: 2)),
        expiryTime: now.add(const Duration(hours: 4)),
        status: 'active',
      ),
      OfferModel(
        id: 'offer_3',
        vendorId: 'vendor_demo_03',
        title: 'Farm Fresh A2 Cow Milk 1L',
        category: 'bakery_dairy',
        description:
            'Pasteurized pure cow milk packets. Same-day clearance discount.',
        oldPrice: 65.0,
        newPrice: 35.0,
        imageUrl: '',
        latitude: 13.0450,
        longitude: 80.2400,
        geohash: GeohashUtils.encode(13.0450, 80.2400),
        createdAt: now.subtract(const Duration(minutes: 90)),
        expiryTime: now.add(const Duration(hours: 2)),
        status: 'active',
      ),
      OfferModel(
        id: 'offer_4',
        vendorId: 'vendor_demo_01',
        title: 'Premium Basmati Rice 5kg Bag',
        category: 'bakery_dairy',
        description: 'Slightly damaged outer packaging sack, rice is 100% sealed & pristine.',
        oldPrice: 450.0,
        newPrice: 280.0,
        imageUrl: '',
        latitude: 13.0402,
        longitude: 80.2337,
        geohash: GeohashUtils.encode(13.0402, 80.2337),
        createdAt: now.subtract(const Duration(hours: 5)),
        expiryTime: now.add(const Duration(hours: 12)),
        status: 'active',
      ),
      OfferModel(
        id: 'offer_5',
        vendorId: 'vendor_demo_04',
        title: 'Assorted Bakery Pastries (Box of 4)',
        category: 'snacks_beverages',
        description:
            'Chocolate éclair, fruit tart, and butter croissants package deal.',
        oldPrice: 220.0,
        newPrice: 100.0,
        imageUrl: '',
        latitude: 13.0350,
        longitude: 80.2250,
        geohash: GeohashUtils.encode(13.0350, 80.2250),
        createdAt: now.subtract(const Duration(hours: 1)),
        expiryTime: now.add(const Duration(hours: 5)),
        status: 'active',
      ),
    ];
  }

  static Map<String, dynamic> getVendorDashboardMetrics() {
    return {
      'activeOffers': 3,
      'viewsToday': 142,
      'customerEnquiries': 18,
      'coverageRadiusKm': 5.0,
      'storeName': 'Green Valley Organics',
      'location': 'T. Nagar, Chennai',
    };
  }
}
