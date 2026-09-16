import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/config/app_config.dart';

void main() {
  test('ships Flutter runtime version 1.0.3 build 6', () {
    expect(kProductVersion, '1.0.3');
    expect(kProductBuild, 6);
  });

  test('publishes matching package and Windows fallback metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final runnerRc = File('windows/runner/Runner.rc').readAsStringSync();

    expect(pubspec, contains('version: 1.0.3+6'));
    expect(runnerRc, contains('#define VERSION_AS_NUMBER 1,0,3,6'));
    expect(runnerRc, contains('#define VERSION_AS_STRING "1.0.3"'));
  });

  test('retains the V1.0.1 Embedded Cronet delivery contract', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final delivery = File('../../FLUTTER-DELIVERY.md').readAsStringSync();

    expect(pubspec, contains('cronet_http: 1.9.0'));
    expect(delivery, contains('Embedded Cronet'));
    expect(delivery, contains('--dart-define=cronetHttpNoPlay=true'));
  });
}
