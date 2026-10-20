import 'package:flutter/material.dart';

import 'router.dart';
import '../features/auth/services/auth_service.dart';
import 'theme.dart';

class SandhaiApp extends StatelessWidget {
  final bool isFirebaseConnected;

  const SandhaiApp({super.key, this.isFirebaseConnected = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) => MaterialApp(
        key: ValueKey(AuthService.instance.routeEpoch),
        title: '5KM Sandhai',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: AppRoutes.welcome,
        onGenerateRoute: (settings) => AppRoutes.generateRoute(
          settings,
          isFirebaseConnected: isFirebaseConnected,
        ),
      ),
    );
  }
}
