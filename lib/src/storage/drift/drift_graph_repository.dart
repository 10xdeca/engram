import 'package:drift/drift.dart';

import '../../models/concept.dart';
import '../../models/knowledge_graph.dart';
import '../../models/quiz_item.dart';
import '../../models/relationship.dart';
import '../graph_repository.dart';
import 'drift_mappers.dart';
import 'engram_database.dart';

/// [GraphRepository] backed by a local Drift/SQLite database.
///
/// Replaces [LocalGraphRepository] (JSON file) for unauthenticated/offline
/// users. Provides reactive [watch] via Drift's table-update streams and
/// efficient single-row updates for quiz reviews.
///
/// All write operations run inside transactions so [watch] listeners see
/// atomic updates. The `save` method uses DELETE ALL + INSERT ALL — this
/// is simpler than Firestore's upsert+diff pattern because SQLite
/// transactions are local and fast.
class DriftGraphRepository extends GraphRepository {
  DriftGraphRepository({required EngramDatabase db}) : _db = db;

  final EngramDatabase _db;

  // -------------------------------------------------------------------------
  // load
  // -------------------------------------------------------------------------

  @override
  Future<KnowledgeGraph> load() async {
    // Query all tables in parallel.
    final results = await Future.wait([
      _db.select(_db.driftConcepts).get(), // 0
      _db.select(_db.driftRelationships).get(), // 1
      _db.select(_db.driftQuizItems).get(), // 2
      _db.select(_db.driftDocuments).get(), // 3
      _db.select(_db.driftTopics).get(), // 4
      _db.select(_db.driftTopicDocuments).get(), // 5
    ]);

    final conceptRows = results[0] as List<DriftConcept>;
    final relationshipRows = results[1] as List<DriftRelationship>;
    final quizItemRows = results[2] as List<DriftQuizItem>;
    final documentRows = results[3] as List<DriftDocument>;
    final topicRows = results[4] as List<DriftTopic>;
    final topicDocRows = results[5] as List<DriftTopicDocument>;

    // Group topic-document join rows by topicId for efficient reconstruction.
    final topicDocMap = <String, Set<String>>{};
    for (final row in topicDocRows) {
      (topicDocMap[row.topicId] ??= {}).add(row.documentId);
    }

    return KnowledgeGraph(
      concepts: conceptRows.map((r) => r.toDomain()).toList(),
      relationships: relationshipRows.map((r) => r.toDomain()).toList(),
      quizItems: quizItemRows.map((r) => r.toDomain()).toList(),
      documentMetadata: documentRows.map((r) => r.toDomain()).toList(),
      topics:
          topicRows
              .map(
                (r) => r.toDomain(documentIds: topicDocMap[r.id] ?? const {}),
              )
              .toList(),
    );
  }

  // -------------------------------------------------------------------------
  // save — DELETE ALL + INSERT ALL inside a transaction
  // -------------------------------------------------------------------------

  @override
  Future<void> save(KnowledgeGraph graph) async {
    await _db.transaction(() async {
      // 1. Delete all existing data.
      await Future.wait([
        _db.delete(_db.driftTopicDocuments).go(),
        _db.delete(_db.driftTopics).go(),
        _db.delete(_db.driftDocuments).go(),
        _db.delete(_db.driftQuizItems).go(),
        _db.delete(_db.driftRelationships).go(),
        _db.delete(_db.driftConcepts).go(),
      ]);

      // 2. Batch-insert all entities.
      await _db.batch((batch) {
        batch.insertAll(
          _db.driftConcepts,
          graph.concepts.map((c) => c.toCompanion()).toList(),
        );
        batch.insertAll(
          _db.driftRelationships,
          graph.relationships.map((r) => r.toCompanion()).toList(),
        );
        batch.insertAll(
          _db.driftQuizItems,
          graph.quizItems.map((q) => q.toCompanion()).toList(),
        );
        batch.insertAll(
          _db.driftDocuments,
          graph.documentMetadata.map((d) => d.toCompanion()).toList(),
        );
        batch.insertAll(
          _db.driftTopics,
          graph.topics.map((t) => t.toCompanion()).toList(),
        );

        // Flatten topic → document join rows.
        for (final topic in graph.topics) {
          for (final docId in topic.documentIds) {
            batch.insert(
              _db.driftTopicDocuments,
              DriftTopicDocumentsCompanion.insert(
                topicId: topic.id,
                documentId: docId,
              ),
            );
          }
        }
      });
    });
  }

  // -------------------------------------------------------------------------
  // updateQuizItem — O(1) single-row write
  // -------------------------------------------------------------------------

  @override
  Future<void> updateQuizItem(KnowledgeGraph graph, QuizItem item) async {
    await _db
        .into(_db.driftQuizItems)
        .insertOnConflictUpdate(item.toCompanion());
  }

  // -------------------------------------------------------------------------
  // saveSplitData — additive only (no deletes)
  // -------------------------------------------------------------------------

  @override
  Future<void> saveSplitData({
    required KnowledgeGraph graph,
    required List<Concept> concepts,
    required List<Relationship> relationships,
    required List<QuizItem> quizItems,
  }) async {
    await _db.batch((batch) {
      batch.insertAll(
        _db.driftConcepts,
        concepts.map((c) => c.toCompanion()).toList(),
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        _db.driftRelationships,
        relationships.map((r) => r.toCompanion()).toList(),
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        _db.driftQuizItems,
        quizItems.map((q) => q.toCompanion()).toList(),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  // -------------------------------------------------------------------------
  // watch — reactive stream
  // -------------------------------------------------------------------------

  /// Emits the full [KnowledgeGraph] on initial subscription and whenever
  /// any table changes.
  ///
  /// Uses Drift's [tableUpdates] to listen for changes across all 6 tables,
  /// then re-loads the entire graph. This is simple and correct — SQLite
  /// reads are fast enough that a full reload on each change is fine for
  /// the expected data sizes (hundreds to low thousands of rows).
  @override
  Stream<KnowledgeGraph> watch() async* {
    // Emit current state immediately.
    yield await load();

    // Then emit on every subsequent table change.
    yield* _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.driftConcepts,
            _db.driftRelationships,
            _db.driftQuizItems,
            _db.driftDocuments,
            _db.driftTopics,
            _db.driftTopicDocuments,
          ]),
        )
        .asyncMap((_) => load());
  }
}
