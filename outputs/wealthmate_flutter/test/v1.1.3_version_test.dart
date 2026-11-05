import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/config/app_config.dart';

void main() {
  test('ships Flutter runtime version 1.1.3 build 17', () {
    expect(kProductVersion, '1.1.3');
    expect(kProductBuild, 17);
  });

  test('publishes matching package and Windows fallback metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final runnerRc = File('windows/runner/Runner.rc').readAsStringSync();

    expect(pubspec, contains('version: 1.1.3+17'));
    expect(runnerRc, contains('#define VERSION_AS_NUMBER 1,1,3,17'));
    expect(runnerRc, contains('#define VERSION_AS_STRING "1.1.3"'));
  });
}
