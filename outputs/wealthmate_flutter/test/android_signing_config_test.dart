import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release uses the controlled original signing configuration', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('WEALTHMATE_SIGNING_PROPERTIES_PATH'));
    expect(gradle, contains('signingConfigs'));
    expect(gradle, contains('create("release")'));
    expect(
      gradle,
      contains('signingConfig = signingConfigs.getByName("release")'),
    );
    expect(
      gradle,
      isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
    );
    expect(gradle, isNot(contains('signingConfig = signingConfigs.debug')));
  });
}
