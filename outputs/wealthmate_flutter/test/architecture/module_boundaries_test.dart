import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _packageRoot() => Directory.current;

Iterable<File> _dartFiles(Directory directory) =>
    directory.listSync(recursive: true).whereType<File>().where(
          (file) => file.path.endsWith('.dart'),
        );

void main() {
  test('feature and UI layers do not reach storage or transport internals', () {
    final root = _packageRoot();
    final featureFiles = _dartFiles(Directory('${root.path}/lib/features')).where(
      (file) => file.path.contains('${Platform.pathSeparator}state${Platform.pathSeparator}') ||
          file.path.contains('${Platform.pathSeparator}ui${Platform.pathSeparator}'),
    );
    final uiFiles = _dartFiles(Directory('${root.path}/lib/ui'));
    for (final file in [...featureFiles, ...uiFiles]) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('drift_database.dart')), reason: file.path);
      expect(source, isNot(contains('local_repository.dart')), reason: file.path);
      expect(source, isNot(contains('api_transport.dart')), reason: file.path);
      expect(source, isNot(contains('http.Client(')), reason: file.path);
    }
  });

  test('feature stores do not write local state or queue directly', () {
    final root = _packageRoot();
    final storeFiles = _dartFiles(Directory('${root.path}/lib/features'))
        .where((file) => file.path.endsWith('_store.dart'));
    for (final file in storeFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('LocalRepository.save')), reason: file.path);
      expect(source, isNot(contains('SyncQueue.enqueue')), reason: file.path);
    }
  });

  test('the app has one SyncCoordinator and one LocalStateSession write seam', () {
    final root = _packageRoot();
    final coordinators = _dartFiles(Directory('${root.path}/lib'))
        .where((file) => file.path.endsWith('sync_coordinator.dart'))
        .toList();
    expect(coordinators, hasLength(1));
    final sessionSource = File(
      '${root.path}/lib/core/database/local_state_session.dart',
    ).readAsStringSync();
    expect(sessionSource, contains('Future<FinanceState> write('));
  });
}
