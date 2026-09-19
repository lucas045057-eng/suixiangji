import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/config/app_config.dart';

void main() {
  test('ships Flutter runtime version 1.0.4 build 7', () {
    expect(kProductVersion, '1.0.4');
    expect(kProductBuild, 7);
  });

  test('publishes matching package and Windows fallback metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final runnerRc = File('windows/runner/Runner.rc').readAsStringSync();

    expect(pubspec, contains('version: 1.0.4+7'));
    expect(runnerRc, contains('#define VERSION_AS_NUMBER 1,0,4,7'));
    expect(runnerRc, contains('#define VERSION_AS_STRING "1.0.4"'));
  });
}
