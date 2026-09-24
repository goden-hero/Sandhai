import 'package:flutter/material.dart';
import '../../../mock_data/mock_data.dart';

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

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _oldPriceController.dispose();
    _newPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableCategories = MockData.categories.where((c) => c != 'All').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Clearance Offer'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAlignment.start,
            children: [
              // Informational Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade900),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Task 2 Form Placeholder: Form UI structure ready. Firestore writes and image upload will be wired in Task 5.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Offer Title Field
              const Text('Offer Title', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'e.g., Organic Alphonso Mangoes 1kg',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 16),

              // Description Field
              const Text('Offer Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g., Surplus clearance stock. Fresh and ready to consume.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),

              // Category Selector Dropdown
              const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
              const SizedBox(height: 16),

              // Price Row (Original vs Clearance Price)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAlignment.start,
                      children: [
                        const Text('Original Price (₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _oldPriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '100'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAlignment.start,
                      children: [
                        const Text('Clearance Price (₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _newPriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '50'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Expiry Duration Selector
              const Text('Offer Validity / Expiry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedDuration,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.timer)),
                items: ['2 Hours', '4 Hours', '6 Hours', '12 Hours', '24 Hours']
                    .map((dur) => DropdownMenuItem(value: dur, child: Text(dur)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDuration = val);
                },
              ),
              const SizedBox(height: 16),

              // Image Selection Box Placeholder
              const Text('Offer Image', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Firebase Storage image upload will be added in Task 5.')),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.grey.shade600),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to select image (Placeholder)',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Submit Action Button (Demo Disabled)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Demo Form: Offer creation will write to Firestore in Task 5.'),
                        backgroundColor: Colors.deepOrange,
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Publish Clearance Offer (Demo Mode)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
