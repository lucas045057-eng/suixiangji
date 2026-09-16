import '../core/database/local_state_session.dart';
import '../core/sync/sync_coordinator.dart';
import 'api_client.dart';
import 'local_repository.dart';
import 'sync_queue.dart';
import '../domain/models.dart';
import '../features/assets/data/assets_remote_data_source.dart';
import '../features/assets/data/assets_repository.dart';
import '../features/ledger/data/ledger_repository.dart';
import '../features/budget/data/budget_remote_data_source.dart';
import '../features/budget/data/budget_repository.dart';

class FinanceRepository {
  FinanceRepository({
    required LocalRepository local,
    required this.queue,
    LocalStateSession? session,
    AssetsRepository? assetsRepository,
    LedgerRepository? ledgerRepository,
    BudgetRepository? budgetRepository,
    this.api,
  })  : _local = local,
        session = session ?? LocalStateSession(local: local, queue: queue) {
    _assetsRepository = assetsRepository ??
        AssetsRepository(
          session: this.session,
          remote: api == null ? null : AssetsRemoteDataSource(api: api!),
        );
    _ledgerRepository =
        ledgerRepository ?? LedgerRepository(session: this.session);
    _budgetRepository = budgetRepository ??
        BudgetRepository(
          session: this.session,
          remote: api == null ? null : BudgetRemoteDataSource(api: api!),
        );
    _syncCoordinator = SyncCoordinator(
      session: this.session,
      api: api,
      isLocalOwnerBound: () => isLocalOwnerBound,
    );
  }

  final LocalRepository _local;
  LocalRepository get local =>
      _localOwnerUserId == null ? _local : _local.forUser(_localOwnerUserId!);
  final SyncQueue queue;
  final LocalStateSession session;
  late final AssetsRepository _assetsRepository;
  late final LedgerRepository _ledgerRepository;
  late final BudgetRepository _budgetRepository;
  late final SyncCoordinator _syncCoordinator;
  final ApiClient? api;
  String? _localOwnerUserId;
  int? _boundApiGeneration;
  int _ownerGeneration = 0;
  int _ownerBindingGeneration = 0;
  Future<void> _ownerBindingTail = Future<void>.value();
  (int, int) get sessionIdentity =>
      (_ownerGeneration, api?.sessionGeneration ?? 0);

  AssetsRepository get assetsRepository => _assetsRepository;

  BudgetRepository get budgetRepository => _budgetRepository;

  String? get localOwnerUserId => _localOwnerUserId;

  bool get isLocalOwnerBound =>
      _localOwnerUserId != null &&
      session.local.userId == _localOwnerUserId &&
      (api == null || _boundApiGeneration == api!.sessionGeneration);

  Future<T> _queueOwnerBinding<T>(Future<T> Function() action) {
    final next = _ownerBindingTail.then<T>((_) => action());
    _ownerBindingTail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// A newly verified identity supersedes any stale recovery that may be
  /// waiting on storage or the network. LocalStateSession still serializes
  /// the actual partition switch, while the generation checks prevent the
  /// superseded operation from publishing state afterward.
  Future<T> _supersedeOwnerBinding<T>(Future<T> Function() action) {
    final next = action();
    _ownerBindingTail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<FinanceState?> loadForUser(String userId) async {
    final generation = api?.sessionGeneration;
    await ensureLocalOwner(userId);
    if (generation != api?.sessionGeneration) return null;
    return load();
  }

  Future<void> ensureLocalOwner(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', '用户身份不能为空');
    }
    await _supersedeOwnerBinding(() => _ensureLocalOwnerNow(normalizedUserId));
  }

  Future<void> _ensureLocalOwnerNow(String normalizedUserId) async {
    final bindingGeneration = ++_ownerBindingGeneration;
    final generation = api?.sessionGeneration;
    await _local.migrateLegacy();
    if (bindingGeneration != _ownerBindingGeneration ||
        generation != api?.sessionGeneration) return;
    final needsRebind = session.local.userId != normalizedUserId;
    if (_localOwnerUserId != normalizedUserId) {
      _ownerGeneration++;
      _syncCoordinator.clearConflictState();
    }
    if (needsRebind) {
      _localOwnerUserId = null;
      _boundApiGeneration = null;
      await session.rebind(_local.forUser(normalizedUserId));
    }
    if (bindingGeneration != _ownerBindingGeneration ||
        generation != api?.sessionGeneration) return;
    _localOwnerUserId = normalizedUserId;
    _boundApiGeneration = generation;
    await _local.saveOwnerUserId(normalizedUserId);
  }

  void unbindLocalOwner() {
    _ownerBindingGeneration++;
    _ownerGeneration++;
    _localOwnerUserId = null;
    _boundApiGeneration = null;
  }

  Future<bool> restoreLocalOwnerForVerifiedSession() =>
      _queueOwnerBinding(_restoreLocalOwnerForVerifiedSessionNow);

  Future<bool> _restoreLocalOwnerForVerifiedSessionNow() async {
    final bindingGeneration = ++_ownerBindingGeneration;
    final generation = api?.sessionGeneration;
    if (api == null || api!.token == null || api!.token!.trim().isEmpty) {
      return false;
    }
    final verifiedUserId = api!.lastVerifiedUserId?.trim();
    if (verifiedUserId == null || verifiedUserId.isEmpty) return false;
    if (isLocalOwnerBound && _localOwnerUserId == verifiedUserId) return true;
    final storedOwner = await _local.loadOwnerUserId();
    if (storedOwner != verifiedUserId &&
        await _local
                .forUser(verifiedUserId)
                .readMetadata(LocalRepository.storageKey) ==
            null) {
      return false;
    }
    if (bindingGeneration != _ownerBindingGeneration ||
        generation != api?.sessionGeneration) return false;
    await _local.migrateLegacy();
    if (bindingGeneration != _ownerBindingGeneration ||
        generation != api?.sessionGeneration) return false;
    if (_localOwnerUserId != verifiedUserId) {
      _ownerGeneration++;
      _syncCoordinator.clearConflictState();
    }
    final needsRebind = session.local.userId != verifiedUserId;
    if (needsRebind) {
      _localOwnerUserId = null;
      _boundApiGeneration = null;
      await session.rebind(_local.forUser(verifiedUserId));
    }
    if (bindingGeneration != _ownerBindingGeneration ||
        generation != api?.sessionGeneration) return false;
    _localOwnerUserId = verifiedUserId;
    _boundApiGeneration = generation;
    await _local.saveOwnerUserId(verifiedUserId);
    return true;
  }

  Future<FinanceState?> load() async {
    await _ownerBindingTail;
    final started = sessionIdentity;
    if (api != null && !isLocalOwnerBound) {
      final restored = await restoreLocalOwnerForVerifiedSession();
      if (sessionIdentity != started) return null;
      if (!restored) {
        await session.mutateQueue((pending) {
          if (sessionIdentity == started) pending.replace(const []);
        });
        return null;
      }
    }
    return session.load();
  }

  Future<void> save(FinanceState state) async {
    await _ownerBindingTail;
    await session.replaceState(state);
  }

  Future<void> persistQueue() async {
    await _ownerBindingTail;
    await session.mutateQueue((_) {});
  }

  Future<void> clearPendingOperations() async {
    await _ownerBindingTail;
    await session.mutateQueue((pending) => pending.replace(const []));
  }

  Future<FinanceState> applyLocal(
      FinanceState state, FinanceTransaction transaction) async {
    return applyLocalTransaction(state, transaction);
  }

  Future<FinanceState> applyLocalTransaction(
      FinanceState state, FinanceTransaction transaction) async {
    await _ownerBindingTail;
    return _ledgerRepository.saveTransaction(transaction, baseState: state);
  }

  /*
   * The remaining aggregate and sync methods stay below this boundary. They
   * use the same session instance, so changing the user only swaps its
   * partition and cache; it does not introduce a second write path.
   */

  Future<FinanceState> applyLocalBudget(
      FinanceState state, Budget budget) async {
    await _ownerBindingTail;
    return _budgetRepository.saveBudget(budget, baseState: state);
  }

  Future<FinanceState> applyLocalAccount(
      FinanceState state, Account account) async {
    await _ownerBindingTail;
    return _assetsRepository.saveAccount(account, baseState: state);
  }

  Future<FinanceState> applyLocalCategory(
      FinanceState state, Category category) async {
    await _ownerBindingTail;
    return _ledgerRepository.saveCategory(category, baseState: state);
  }

  Future<FinanceState> softDelete(
      FinanceState state, String transactionId) async {
    await _ownerBindingTail;
    return _ledgerRepository.deleteTransaction(transactionId, baseState: state);
  }

  Future<FinanceState> sync(FinanceState state,
      {bool Function()? isCurrent}) async {
    await _ownerBindingTail;
    final started = sessionIdentity;
    return _syncCoordinator.sync(state,
        isCurrent: isCurrent ?? () => sessionIdentity == started);
  }

  Future<FinanceState> pushPending(FinanceState state) async {
    await _ownerBindingTail;
    final started = sessionIdentity;
    return _syncCoordinator.pushPending(state,
        isCurrent: () => sessionIdentity == started);
  }

  Future<FinanceState> pullChanges(FinanceState state) async {
    await _ownerBindingTail;
    final started = sessionIdentity;
    return _syncCoordinator.pullChanges(state,
        isCurrent: () => sessionIdentity == started);
  }

  FinanceState mergePulled(FinanceState localState,
          List<FinanceTransaction> remoteTransactions) =>
      _syncCoordinator.mergePulled(localState, remoteTransactions);

  FinanceState mergePulledAccounts(
          FinanceState localState, List<Account> remoteAccounts) =>
      _syncCoordinator.mergePulledAccounts(localState, remoteAccounts);

  FinanceState mergePulledCategories(
          FinanceState localState, List<Category> remoteCategories) =>
      _syncCoordinator.mergePulledCategories(localState, remoteCategories);

  FinanceState mergePulledBudgets(
          FinanceState localState, List<Budget> remoteBudgets) =>
      _syncCoordinator.mergePulledBudgets(localState, remoteBudgets);
}
