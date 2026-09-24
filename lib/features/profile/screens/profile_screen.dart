import 'package:flutter/material.dart';
import '../../../app/router.dart';
import '../../../models/user_model.dart';
import '../../auth/services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  final String userRole;
  final bool isFirebaseConnected;

  const ProfileScreen({
    super.key,
    required this.userRole,
    this.isFirebaseConnected = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;
  late UserModel _userProfile;

  @override
  void initState() {
    super.initState();
    _userProfile = AuthService.instance.demoCurrentUser ??
        UserModel(
          uid: 'user_profile_demo',
          displayName: widget.userRole == 'vendor' ? 'Green Valley Organics' : 'Demo Customer User',
          email: widget.userRole == 'vendor' ? 'vendor@greenvalley.com' : 'customer@example.com',
          role: widget.userRole,
          approvalStatus: widget.userRole == 'vendor' ? 'pending' : 'approved',
          createdAt: DateTime.now(),
        );
  }

  Future<void> _handleSignOut() async {
    await AuthService.instance.signOut();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed out successfully.'),
        duration: Duration(seconds: 1),
      ),
    );

    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.welcome, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final isVendor = _userProfile.role == 'vendor';
    final isPending = _userProfile.isPendingVendor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          // User Avatar & Name Header
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  child: Icon(
                    isVendor ? Icons.storefront : Icons.person,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _userProfile.displayName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _userProfile.email,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isVendor ? Colors.green.shade100 : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isVendor ? 'VENDOR ROLE' : 'CUSTOMER ROLE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isVendor ? Colors.green.shade900 : Colors.blue.shade900,
                        ),
                      ),
                    ),
                    if (isVendor) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPending ? Colors.amber.shade100 : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isPending ? 'APPROVAL PENDING' : 'VERIFIED STORE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPending ? Colors.amber.shade900 : Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          const Text('Account Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),

          ListTile(
            leading: const Icon(Icons.fingerprint_outlined),
            title: const Text('Firebase UID'),
            subtitle: Text(_userProfile.uid, style: const TextStyle(fontSize: 12)),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Default Location'),
            subtitle: const Text('T. Nagar, Chennai (Mock 5 KM Radius)'),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Push Notifications'),
            subtitle: Text(_notificationsEnabled
                ? 'Enabled: FCM alerts for nearby 5 KM offers'
                : 'Disabled: No local clearance notifications'),
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: (val) {
                setState(() => _notificationsEnabled = val);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(val
                        ? 'Push notifications enabled.'
                        : 'Push notifications disabled.'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Firebase Auth Status'),
            subtitle: Text(
              widget.isFirebaseConnected
                  ? 'Connected: Firebase Authentication & Emulators Active'
                  : 'Standalone Demo Mode Active',
            ),
            trailing: Icon(
              widget.isFirebaseConnected ? Icons.check_circle : Icons.offline_bolt_outlined,
              color: widget.isFirebaseConnected ? Colors.green : Colors.orange,
            ),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About 5KM Sandhai'),
            subtitle: const Text('Version 1.0.0 (Task 3 Auth Integration Active)'),
          ),
          const SizedBox(height: 24),

          // Real Sign Out Button
          OutlinedButton.icon(
            onPressed: _handleSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
