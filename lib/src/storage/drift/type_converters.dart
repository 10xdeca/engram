import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../models/relationship.dart';

/// Converts an [IList<String>] to/from a JSON-encoded TEXT column.
///
/// Used for the `tags` field on concepts, which is a list of strings that
/// we never query independently — so JSON TEXT is more efficient than a
/// separate join table.
class IListStringConverter extends TypeConverter<IList<String>, String> {
  const IListStringConverter();

  @override
  IList<String> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb) as List<dynamic>;
    return decoded.map((e) => e as String).toIList();
  }

  @override
  String toSql(IList<String> value) {
    return jsonEncode(value.toList());
  }
}

/// Converts a [RelationshipType] to/from its [name] as a TEXT column.
///
/// Stores the enum's Dart name (e.g. `'prerequisite'`, `'composition'`).
/// On read, falls back to [RelationshipType.relatedTo] for unknown values
/// to handle forward compatibility if new types are added later.
class RelationshipTypeConverter
    extends TypeConverter<RelationshipType, String> {
  const RelationshipTypeConverter();

  @override
  RelationshipType fromSql(String fromDb) {
    return RelationshipType.tryParse(fromDb) ?? RelationshipType.relatedTo;
  }

  @override
  String toSql(RelationshipType value) {
    return value.name;
  }
}
