import 'package:flutter/material.dart';

import '../features/auth/screens/session_gate.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/auth/screens/register_customer_screen.dart';
import '../features/auth/screens/register_vendor_screen.dart';
import '../features/customer/screens/customer_home_screen.dart';
import '../features/vendor/screens/vendor_dashboard_screen.dart';
import '../features/vendor/screens/create_offer_screen.dart';
import '../features/vendor/screens/vendor_profile_screen.dart';
import '../features/profile/screens/profile_screen.dart';

class AppRoutes {
  static const String welcome = '/';
  static const String signIn = '/auth/sign-in';
  static const String registerCustomer = '/auth/register-customer';
  static const String registerVendor = '/auth/register-vendor';
  static const String customerHome = '/customer/home';
  static const String vendorDashboard = '/vendor/dashboard';
  static const String createOffer = '/vendor/create-offer';
  static const String vendorProfile = '/vendor/profile';
  static const String profile = '/profile';

  static Route<dynamic> generateRoute(
    RouteSettings settings, {
    bool isFirebaseConnected = false,
  }) {
    switch (settings.name) {
      case welcome:
        return MaterialPageRoute(builder: (_) => const SessionGate());
      case signIn:
        return MaterialPageRoute(builder: (_) => const SignInScreen());
      case registerCustomer:
        return MaterialPageRoute(
          builder: (_) => const RegisterCustomerScreen(),
        );
      case registerVendor:
        return MaterialPageRoute(builder: (_) => const RegisterVendorScreen());
      case customerHome:
        return MaterialPageRoute(
          builder: (_) => const SessionGuard(child: CustomerHomeScreen()),
        );
      case vendorDashboard:
        return MaterialPageRoute(
          builder: (_) => const SessionGuard(
            vendorOnly: true,
            child: VendorDashboardScreen(),
          ),
        );
      case createOffer:
        return MaterialPageRoute(
          builder: (_) =>
              const SessionGuard(vendorOnly: true, child: CreateOfferScreen()),
        );
      case vendorProfile:
        return MaterialPageRoute(
          builder: (_) => const SessionGuard(
            vendorOnly: true,
            child: VendorProfileScreen(),
          ),
        );
      case profile:
        final role = settings.arguments as String? ?? 'customer';
        if (role == 'vendor') {
          return MaterialPageRoute(
            builder: (_) => const SessionGuard(
              vendorOnly: true,
              child: VendorProfileScreen(),
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => SessionGuard(
            child: ProfileScreen(
              userRole: role,
              isFirebaseConnected: isFirebaseConnected,
            ),
          ),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
