import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/config/app_config.dart';

void main() {
  test('ships Flutter runtime version 1.1.2 build 16', () {
    expect(kProductVersion, '1.1.2');
    expect(kProductBuild, 16);
  });

  test('publishes matching package and Windows fallback metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final runnerRc = File('windows/runner/Runner.rc').readAsStringSync();

    expect(pubspec, contains('version: 1.1.2+15'));
    expect(runnerRc, contains('#define VERSION_AS_NUMBER 1,1,2,16'));
    expect(runnerRc, contains('#define VERSION_AS_STRING "1.1.2"'));
  });
}
