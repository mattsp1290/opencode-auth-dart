import 'dart:convert';

import 'errors.dart';

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

List<OpenCodeModel> decodeOpenCodeCatalog(List<int> bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const OpenCodeProtocolException();
  }
  if (decoded is! Map<String, Object?> ||
      decoded['object'] != 'list' ||
      decoded['data'] is! List<Object?>) {
    throw const OpenCodeProtocolException();
  }
  final models = <OpenCodeModel>[];
  for (final item in decoded['data']! as List<Object?>) {
    if (item is! Map<String, Object?>) {
      throw const OpenCodeProtocolException();
    }
    final id = item['id'];
    final object = item['object'];
    final created = item['created'];
    final ownedBy = item['owned_by'];
    if (id is! String ||
        id.isEmpty ||
        (object != null && object is! String) ||
        (created != null && created is! int) ||
        (ownedBy != null && ownedBy is! String)) {
      throw const OpenCodeProtocolException();
    }
    models.add(
      OpenCodeModel(
        id: id,
        object: object as String?,
        created: created as int?,
        ownedBy: ownedBy as String?,
      ),
    );
  }
  return List<OpenCodeModel>.unmodifiable(models);
}
