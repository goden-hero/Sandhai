import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/app/config.dart';

void main() {
  test(
    'browser emulator uses loopback even with Android as target platform',
    () {
      final config = AppConfig.parse(mode: 'emulator', isWeb: true);
      expect(config.emulatorHost, '127.0.0.1');
    },
  );

  test('Android emulator uses the host machine alias', () {
    final config = AppConfig.parse(mode: 'emulator');
    expect(config.emulatorHost, '10.0.2.2');
  });

  test('a physical device can use a configured LAN host', () {
    final config = AppConfig.parse(
      mode: 'emulator',
      emulatorHost: '192.168.1.20',
    );
    expect(config.emulatorHost, '192.168.1.20');
  });

  test('demo and production remain explicit on Android and web', () {
    for (final isWeb in [false, true]) {
      for (final mode in [AppMode.demo, AppMode.production]) {
        final config = AppConfig.parse(
          mode: mode.name,
          isWeb: isWeb,
          platform: TargetPlatform.android,
        );
        expect(config.mode, mode);
      }
    }
  });

  test('a misspelled mode cannot silently select demo', () {
    expect(() => AppConfig.parse(mode: 'prodution'), throwsArgumentError);
  });

  test('emulator hosts exclude schemes, paths, ports, and whitespace', () {
    for (final host in [
      'http://localhost',
      'localhost/path',
      'localhost:8080',
      ' ',
    ]) {
      expect(
        () => AppConfig.parse(mode: 'emulator', emulatorHost: host),
        throwsArgumentError,
      );
    }
  });
}
