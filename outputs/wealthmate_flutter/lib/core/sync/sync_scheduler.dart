import 'dart:async';

typedef SyncPipeline = Future<bool> Function();
typedef SyncEligibility = bool Function();

/// Serializes sync requests into one debounced, continuously draining Future.
///
/// A request received while a pipeline is active marks the drain dirty and
/// joins the same Future. A failed round ends the drain; the next external
/// request is responsible for waking it again.
class SyncScheduler {
  SyncScheduler({
    required this.runPipeline,
    required this.canRun,
    this.debounce = const Duration(milliseconds: 250),
  });

  final SyncPipeline runPipeline;
  final SyncEligibility canRun;
  final Duration debounce;

  Timer? _debounceTimer;
  Future<void>? _drainFuture;
  Completer<void>? _drainCompleter;
  bool _dirty = false;
  bool _active = false;
  bool _disposed = false;

  bool get isActive => _active;

  Future<void> request({String reason = 'unknown', bool immediate = false}) {
    if (_disposed) return Future<void>.value();
    _dirty = true;
    final active = _drainFuture;
    if (active != null) {
      if (immediate && !_active) _startDrain();
      return active;
    }

    final completer = Completer<void>();
    _drainFuture = completer.future;
    _drainCompleter = completer;
    if (immediate) {
      _startDrain();
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, _startDrain);
    }
    return completer.future;
  }

  void _startDrain() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_active || _disposed) return;
    final completer = _drainCompleter;
    if (completer == null) return;
    _active = true;
    unawaited(_drain(completer));
  }

  Future<void> _drain(Completer<void> completer) async {
    try {
      if (!canRun()) {
        return;
      }
      while (_dirty) {
        _dirty = false;
        final succeeded = await _runSafely();
        if (!succeeded) return;
      }
    } finally {
      _active = false;
      if (identical(_drainCompleter, completer)) {
        _drainCompleter = null;
        _drainFuture = null;
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<bool> _runSafely() async {
    try {
      return await runPipeline();
    } on Object {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
