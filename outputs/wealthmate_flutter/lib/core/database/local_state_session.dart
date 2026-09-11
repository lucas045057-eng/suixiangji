import '../../data/local_repository.dart';
import '../../data/sync_queue.dart';
import '../../domain/models.dart';

typedef StateMutation = FinanceState Function(FinanceState current);

/// Serializes access to the locally persisted finance aggregate and queue.
class LocalStateSession {
  LocalStateSession({required LocalRepository local, required this.queue})
      : _local = local;

  LocalRepository _local;
  final SyncQueue queue;
  Future<void> _tail = Future<void>.value();
  FinanceState? _state;
  bool _loaded = false;

  LocalRepository get local => _local;

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_, __) {});
    return run;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _state = await local.load();
    if (queue.pending().isEmpty) {
      queue.replace(await local.loadQueue());
    }
    _loaded = true;
  }

  /// Rebinds the aggregate cache and queue to a verified user's partition.
  /// The rebind itself is serialized with all pending aggregate writes.
  Future<void> rebind(LocalRepository local) => _serial(() async {
        _local = local;
        _state = null;
        _loaded = false;
        queue.replace(await _local.loadQueue());
      });

  /// Serializes deletion of a partition with normal aggregate writes.
  Future<void> purgePartition(LocalRepository partition) =>
      _serial(partition.purge);

  Future<FinanceState?> load() => _serial(() async {
        await _ensureLoaded();
        return _state;
      });

  Future<FinanceState> write(
    StateMutation mutation, {
    Iterable<SyncOperation> appendOperations = const [],
  }) =>
      _serial(() async {
        await _ensureLoaded();
        final next = mutation(_state ?? const FinanceState());
        for (final operation in appendOperations) {
          queue.enqueue(operation);
        }
        await local.save(next);
        await local.saveQueue(queue);
        _state = next;
        return next;
      });

  Future<FinanceState> replaceState(FinanceState next) => _serial(() async {
        await _ensureLoaded();
        await local.save(next);
        await local.saveQueue(queue);
        _state = next;
        return next;
      });

  Future<void> mutateQueue(void Function(SyncQueue queue) mutation) =>
      _serial(() async {
        await _ensureLoaded();
        mutation(queue);
        await local.saveQueue(queue);
      });

  Future<List<SyncOperation>> pendingOperations() => _serial(() async {
        await _ensureLoaded();
        return queue.pending();
      });
}
