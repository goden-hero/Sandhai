/// Persist IDs, display labels. Missing/unknown legacy values become `other`.
class OfferCategories {
  static const labels = <String, String>{
    'groceries': 'Groceries',
    'fresh_produce': 'Fresh Produce',
    'bakery_dairy': 'Bakery & Dairy',
    'snacks_beverages': 'Snacks & Beverages',
    'services': 'Services',
    'other': 'Other',
  };
  static const values = ['All', ...ids];
  static const ids = [
    'groceries',
    'fresh_produce',
    'bakery_dairy',
    'snacks_beverages',
    'services',
    'other',
  ];
  static String label(String id) =>
      labels[id] ?? (id == 'All' ? 'All' : 'Other');
  static String normalize(Object? value) {
    if (ids.contains(value)) return value as String;
    for (final entry in labels.entries) {
      if (entry.value == value) return entry.key;
    }
    return 'other';
  }
}
