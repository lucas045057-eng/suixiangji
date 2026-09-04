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
  });

  final String clientOpId;
  final String entity;
  final String entityId;
  final SyncOperationType type;
  final Map<String, Object?> payload;
  final String? createdAt;

  Map<String, Object?> toJson() => {
        'client_op_id': clientOpId,
        'entity': entity,
        'entity_id': entityId,
        'type': syncOperationTypeToJson(type),
        'payload': payload,
        'created_at': createdAt,
      };

  factory SyncOperation.fromJson(Map<String, Object?> json) => SyncOperation(
        clientOpId: json['client_op_id']! as String,
        entity: json['entity']! as String,
        entityId: json['entity_id']! as String,
        type: syncOperationTypeFromJson(json['type']),
        payload: (json['payload'] as Map).cast<String, Object?>(),
        createdAt: json['created_at'] as String?,
      );
}

class SyncQueue {
  SyncQueue([List<SyncOperation>? initial]) {
    if (initial != null) _items.addAll(initial);
    deduplicate();
  }

  final List<SyncOperation> _items = [];

  void enqueue(SyncOperation operation) {
    if (_items.any((item) => item.clientOpId == operation.clientOpId)) return;
    // Only the latest mutation for an entity needs to travel over the wire.
    // This prevents an offline create/update followed by delete from replaying
    // stale operations and keeps the queue idempotent at entity level.
    final index = _items.indexWhere((item) =>
        item.entity == operation.entity && item.entityId == operation.entityId);
    if (index >= 0) {
      _items[index] = operation;
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
