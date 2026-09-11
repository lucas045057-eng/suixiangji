import '../../data/local_repository.dart';
import '../../data/sync_queue.dart';
import '../../domain/models.dart';

typedef StateMutation = FinanceState Function(FinanceState current);

class _SessionContext {
  _SessionContext(this.local, this.queue);

  final LocalRepository local;
  SyncQueue queue;
  Future<void> tail = Future<void>.value();
  FinanceState? state;
  bool loaded = false;
}

/// Serializes access to the locally persisted finance aggregate and queue.
class LocalStateSession {
  LocalStateSession({required LocalRepository local, required this.queue})
      : _current = _SessionContext(local, queue) {
    _contexts.add(_current);
  }

  final SyncQueue queue;
  final List<_SessionContext> _contexts = <_SessionContext>[];
  _SessionContext _current;
  int _bindingGeneration = 0;

  LocalRepository get local => _current.local;

  Future<T> _serial<T>(
      _SessionContext context, Future<T> Function() action) {
    final run = context.tail.then((_) => action());
    context.tail = run.then<void>((_) {}, onError: (_, __) {});
    return run;
  }

  Future<void> _ensureLoaded(_SessionContext context) async {
    if (context.loaded) return;
    context.state = await context.local.load();
    if (context.queue.pending().isEmpty) {
      context.queue.replace(await context.local.loadQueue());
    }
    context.loaded = true;
  }

  /// Rebinds the aggregate cache and queue to a verified user's partition.
  ///
  /// The old context remains serialized independently while its in-flight
  /// writes finish against the old partition. The public queue is switched
  /// only after the new context has loaded its partition.
  Future<void> rebind(LocalRepository local) async {
    final generation = ++_bindingGeneration;
    final previous = _current;
    final previousOperations = previous.queue.pending();
    if (identical(previous.queue, queue)) {
      previous.queue = SyncQueue(previousOperations);
    }
    queue.replace(const []);
    final next = _SessionContext(local, queue);
    await _ensureLoaded(next);
    if (generation != _bindingGeneration) return;
    _contexts.add(next);
    _current = next;
    queue.replace(next.queue.pending());
  }

  /// Serializes deletion of a partition with normal aggregate writes.
  Future<void> purgePartition(LocalRepository partition) {
    final matches = _contexts.where((context) =>
        context.local.userId == partition.userId &&
        identical(context.local.store, partition.store));
    final context = matches.isEmpty
        ? _SessionContext(partition, SyncQueue())
        : matches.last;
    if (!_contexts.contains(context)) _contexts.add(context);
    return _serial(context, () async {
      await partition.purge();
      context.state = null;
      context.loaded = false;
      context.queue.replace(const []);
      if (identical(_current, context)) queue.replace(const []);
    });
  }

  Future<FinanceState?> load() {
    final context = _current;
    return _serial(context, () async {
      await _ensureLoaded(context);
      return context.state;
    });
  }

  Future<FinanceState> write(
    StateMutation mutation, {
    Iterable<SyncOperation> appendOperations = const [],
  }) {
    final context = _current;
    return _serial(context, () async {
      await _ensureLoaded(context);
      final next = mutation(context.state ?? const FinanceState());
      for (final operation in appendOperations) {
        context.queue.enqueue(operation);
      }
      await context.local.save(next);
      await context.local.saveQueue(context.queue);
      context.state = next;
      return next;
    });
  }

  Future<FinanceState> replaceState(FinanceState next) {
    final context = _current;
    return _serial(context, () async {
      await _ensureLoaded(context);
      await context.local.save(next);
      await context.local.saveQueue(context.queue);
      context.state = next;
      return next;
    });
  }

  Future<void> mutateQueue(void Function(SyncQueue queue) mutation) {
    final context = _current;
    return _serial(context, () async {
      await _ensureLoaded(context);
      mutation(context.queue);
      await context.local.saveQueue(context.queue);
    });
  }

  Future<List<SyncOperation>> pendingOperations() {
    final context = _current;
    return _serial(context, () async {
      await _ensureLoaded(context);
      return context.queue.pending();
    });
  }
}
