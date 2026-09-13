final class OpenCodeModel {
  const OpenCodeModel({
    required this.id,
    this.object,
    this.created,
    this.ownedBy,
  });

  final String id;
  final String? object;
  final int? created;
  final String? ownedBy;

  @override
  String toString() => 'OpenCodeModel(id: $id)';
}
