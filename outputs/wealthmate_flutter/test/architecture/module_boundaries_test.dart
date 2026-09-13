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
    final featureFiles = _dartFiles(Directory('${root.path}/lib/features'));
    for (final file in featureFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('local.save(')), reason: file.path);
      expect(source, isNot(contains('local.saveQueue(')), reason: file.path);
      expect(source, isNot(contains('queue.enqueue(')), reason: file.path);
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

  test('ApiClient keeps compatibility methods but no endpoint implementations', () {
    final source = File(
      '${_packageRoot().path}/lib/data/api_client.dart',
    ).readAsStringSync();
    for (final endpoint in <String>[
      '/auth/login',
      '/auth/register',
      '/auth/me',
      '/auth/password',
      '/accounts',
      '/categories',
      '/transactions',
      '/budgets',
      '/stats',
      '/wealth',
      '/reports/monthly',
      '/backup/export',
      '/backup/restore',
      '/agent/draft',
      '/sync/push',
      '/sync/pull',
    ]) {
      expect(source, isNot(contains(endpoint)), reason: endpoint);
    }
  });

  test('production HTTP construction stays inside the platform factory', () {
    final root = _packageRoot();
    final productionFiles = _dartFiles(Directory('${root.path}/lib'));
    final factoryFiles = productionFiles.where(
      (file) => file.path.contains(
        '${Platform.pathSeparator}core${Platform.pathSeparator}network${Platform.pathSeparator}http_client_factory',
      ),
    );

    for (final file in productionFiles) {
      final source = file.readAsStringSync();
      if (!factoryFiles.contains(file)) {
        expect(source, isNot(contains('http.Client(')), reason: file.path);
        expect(source, isNot(contains('http.Client.new')), reason: file.path);
        expect(source, isNot(contains('CronetClient')), reason: file.path);
        expect(source, isNot(contains('CronetEngine')), reason: file.path);
        expect(source, isNot(contains('package:cronet_http')), reason: file.path);
        expect(source, isNot(contains('HttpClient(')), reason: file.path);
      }
    }

    for (final fileName in <String>[
      'http_client_factory_web.dart',
      'http_client_factory_stub.dart',
    ]) {
      final source = File(
        '${root.path}/lib/core/network/$fileName',
      ).readAsStringSync();
      expect(source, isNot(contains('package:cronet_http')),
          reason: fileName);
      expect(source, isNot(contains('dart:io')), reason: fileName);
    }
  });
}
