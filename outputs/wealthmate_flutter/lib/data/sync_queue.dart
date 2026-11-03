enum SyncOperationType { upsert, delete }

String syncOperationTypeToJson(SyncOperationType value) => value.name;

SyncOperationType syncOperationTypeFromJson(Object? value) =>
    value == 'delete' ? SyncOperationType.delete : SyncOperationType.upsert;

class SyncOperation {
  const SyncOperation({
    required this.clientOpId,
    required this.entity,
    required this.entityId,
    required this.type,
    required this.payload,
    this.createdAt,
    this.conflictClientOpId,
    this.submittedOperation,
    this.baseVersion,
    this.base,
  });

  final String clientOpId;
  final String entity;
  final String entityId;
  final SyncOperationType type;
  final Map<String, Object?> payload;
  final String? createdAt;
  final String? conflictClientOpId;
  final Map<String, Object?>? submittedOperation;

  /// Entity version read when the user started editing. Never fabricated: a
  /// create or an entity without a known authoritative version leaves it null.
  final int? baseVersion;

  /// Field snapshot of the same authoritative version, used for V2 three-way
  /// field merging and for rolling a rejected optimistic edit back.
  final Map<String, Object?>? base;

  Map<String, Object?> toJson() => {
        'client_op_id': clientOpId,
        'entity': entity,
        'entity_id': entityId,
        'type': syncOperationTypeToJson(type),
        'payload': payload,
        'created_at': createdAt,
        if (conflictClientOpId != null)
          'conflict_client_op_id': conflictClientOpId,
        if (submittedOperation != null)
          'submitted_operation': submittedOperation,
        if (baseVersion != null) 'base_version': baseVersion,
        if (base != null) 'base': base,
      };

  factory SyncOperation.fromJson(Map<String, Object?> json) => SyncOperation(
        clientOpId: json['client_op_id']! as String,
        entity: json['entity']! as String,
        entityId: json['entity_id']! as String,
        type: syncOperationTypeFromJson(json['type']),
        payload: (json['payload'] as Map).cast<String, Object?>(),
        createdAt: json['created_at'] as String?,
        conflictClientOpId: json['conflict_client_op_id'] as String?,
        submittedOperation:
            (json['submitted_operation'] as Map?)?.cast<String, Object?>(),
        baseVersion: (json['base_version'] as num?)?.toInt(),
        base: (json['base'] as Map?)?.cast<String, Object?>(),
      );

  SyncOperation copyWith({
    String? clientOpId,
    String? entity,
    String? entityId,
    SyncOperationType? type,
    Map<String, Object?>? payload,
    String? createdAt,
    String? conflictClientOpId,
    Map<String, Object?>? submittedOperation,
    int? baseVersion,
    Map<String, Object?>? base,
  }) =>
      SyncOperation(
        clientOpId: clientOpId ?? this.clientOpId,
        entity: entity ?? this.entity,
        entityId: entityId ?? this.entityId,
        type: type ?? this.type,
        payload: payload ?? this.payload,
        createdAt: createdAt ?? this.createdAt,
        conflictClientOpId: conflictClientOpId ?? this.conflictClientOpId,
        submittedOperation: submittedOperation ?? this.submittedOperation,
        baseVersion: baseVersion ?? this.baseVersion,
        base: base ?? this.base,
      );
}

class SyncQueue {
  SyncQueue([List<SyncOperation>? initial]) {
    if (initial != null) _items.addAll(initial);
    deduplicate();
  }

  final List<SyncOperation> _items = [];

  void enqueue(SyncOperation operation) {
    final entityIndex = _items.indexWhere((item) =>
        item.entity == operation.entity && item.entityId == operation.entityId);
    if (entityIndex >= 0) {
      final existing = _items[entityIndex];
      // Keep the baseline the user actually saw. A later offline edit must not
      // replace it with an intermediate local snapshot.
      if (existing.base != null || existing.baseVersion != null) {
        operation = operation.copyWith(
            baseVersion: existing.baseVersion, base: existing.base);
      }
      if ((existing.conflictClientOpId != null &&
              operation.conflictClientOpId == null) ||
          (existing.submittedOperation != null &&
              operation.submittedOperation == null)) {
        operation = SyncOperation(
            clientOpId: operation.clientOpId,
            entity: operation.entity,
            entityId: operation.entityId,
            type: operation.type,
            payload: operation.payload,
            createdAt: operation.createdAt,
            conflictClientOpId:
                operation.conflictClientOpId ?? existing.conflictClientOpId,
            submittedOperation:
                operation.submittedOperation ?? existing.submittedOperation,
            baseVersion: operation.baseVersion ?? existing.baseVersion,
            base: operation.base ?? existing.base);
      }
      if (existing.clientOpId == operation.clientOpId &&
          existing.type == SyncOperationType.upsert &&
          operation.type == SyncOperationType.upsert) {
        // A pending create/edit shares one client operation identity. Keep
        // that identity while replacing the complete latest snapshot.
        _items[entityIndex] = operation;
        return;
      }
    }
    if (_items.any((item) => item.clientOpId == operation.clientOpId)) return;
    // Only the latest mutation for an entity needs to travel over the wire.
    // This prevents an offline create/update followed by delete from replaying
    // stale operations and keeps the queue idempotent at entity level.
    if (entityIndex >= 0) {
      _items[entityIndex] = operation;
    } else {
      _items.add(operation);
    }
  }

  List<SyncOperation> pending() => List.unmodifiable(_items);

  void complete(String clientOpId) {
    _items.removeWhere((item) => item.clientOpId == clientOpId);
  }

  void deduplicate() {
    final seen = <String>{};
    _items.removeWhere((item) => !seen.add(item.clientOpId));
  }

  void replace(Iterable<SyncOperation> operations) {
    _items
      ..clear()
      ..addAll(operations);
    deduplicate();
  }

  List<Map<String, Object?>> toJson() =>
      _items.map((item) => item.toJson()).toList();
}
