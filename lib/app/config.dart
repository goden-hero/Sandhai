import 'package:flutter/foundation.dart';

enum AppMode { demo, emulator, production }

/// Build-time selection; build type (debug/release) never selects a backend.
class AppConfig {
  const AppConfig({
    required this.mode,
    this.emulatorHost = '127.0.0.1',
    this.emulatorProjectId = 'sandhai-5km-demo',
  });

  final AppMode mode;
  final String emulatorHost;
  final String emulatorProjectId;

  bool get isDemo => mode == AppMode.demo;

  // Assigned before the first route or service is constructed.
  static AppConfig current = const AppConfig(mode: AppMode.demo);

  factory AppConfig.fromEnvironment() => AppConfig.parse(
    mode: const String.fromEnvironment('APP_MODE', defaultValue: 'demo'),
    emulatorHost: const String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
    emulatorProjectId: const String.fromEnvironment(
      'FIREBASE_EMULATOR_PROJECT_ID',
      defaultValue: 'sandhai-5km-demo',
    ),
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  factory AppConfig.parse({
    required String mode,
    String emulatorHost = '',
    String emulatorProjectId = 'sandhai-5km-demo',
    bool isWeb = false,
    TargetPlatform platform = TargetPlatform.android,
  }) {
    final selectedMode = switch (mode) {
      'demo' => AppMode.demo,
      'emulator' => AppMode.emulator,
      'production' => AppMode.production,
      _ => throw ArgumentError.value(
        mode,
        'APP_MODE',
        'Expected demo, emulator, or production.',
      ),
    };
    final host = emulatorHost.isEmpty
        ? (!isWeb && platform == TargetPlatform.android
              ? '10.0.2.2'
              : '127.0.0.1')
        : emulatorHost.trim();
    if (selectedMode == AppMode.emulator &&
        (host.isEmpty || host.contains(RegExp(r'[\s/]')))) {
      throw ArgumentError.value(
        emulatorHost,
        'FIREBASE_EMULATOR_HOST',
        'Use a hostname or IP address without a scheme, port, or path.',
      );
    }
    // IPv6 literals may contain colons; host:port must not override fixed ports.
    if (selectedMode == AppMode.emulator &&
        host.contains(':') &&
        !host.contains('::')) {
      throw ArgumentError.value(
        emulatorHost,
        'FIREBASE_EMULATOR_HOST',
        'Do not include a port; Auth/Firestore/Storage use 9099/8080/9199.',
      );
    }
    return AppConfig(
      mode: selectedMode,
      emulatorHost: host,
      emulatorProjectId: emulatorProjectId,
    );
  }
}
