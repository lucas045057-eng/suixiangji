List<Map<String, Object?>> responseItems(Map<String, Object?> json) {
  final values =
      (json['items'] ?? json['data'] ?? const <Object?>[]) as List<Object?>;
  return values
      .map((item) => (item! as Map).cast<String, Object?>())
      .toList();
}
