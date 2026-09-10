import '../../data/local_repository.dart';
import '../../data/sync_queue.dart';
import '../../domain/models.dart';

typedef StateMutation = FinanceState Function(FinanceState current);

/// Serializes access to the locally persisted finance aggregate and queue.
class LocalStateSession {
  LocalStateSession({required this.local, required this.queue});

  final LocalRepository local;
  final SyncQueue queue;
  Future<void> _tail = Future<void>.value();
  FinanceState? _state;
  bool _loaded = false;

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
