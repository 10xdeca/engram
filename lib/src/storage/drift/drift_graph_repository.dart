import 'package:drift/drift.dart';

import '../../crdt/hlc_manager.dart';
import '../../models/concept.dart';
import '../../models/knowledge_graph.dart';
import '../../models/quiz_item.dart';
import '../../models/relationship.dart';
import '../graph_repository.dart';
import 'drift_mappers.dart';
import 'engram_database.dart';

/// [GraphRepository] backed by a local Drift/SQLite database.
///
/// Primary storage for unauthenticated/offline users. Provides reactive
/// [watch] via Drift's table-update streams and efficient single-row
/// updates for quiz reviews.
///
/// All write operations run inside transactions so [watch] listeners see
/// atomic updates. The `save` method uses DELETE ALL + INSERT ALL — this
/// is simpler than Firestore's upsert+diff pattern because SQLite
/// transactions are local and fast.
///
/// When an [HlcManager] is provided, every write is stamped with a
/// Hybrid Logical Clock timestamp for CRDT sync (#41). Rows with
/// `isDeleted = true` are excluded from [load] results but preserved
/// in the database for changeset propagation.
class DriftGraphRepository extends GraphRepository {
  DriftGraphRepository({required EngramDatabase db, HlcManager? hlcManager})
      : _db = db,
        _hlcManager = hlcManager;

  final EngramDatabase _db;
  final HlcManager? _hlcManager;

  /// Returns the current HLC string for stamping writes, or empty string
  /// if no HlcManager is configured (backward compatible).
  String _stampHlc() => _hlcManager?.now().toString() ?? '';

  // -------------------------------------------------------------------------
  // load
  // -------------------------------------------------------------------------

  @override
  Future<KnowledgeGraph> load() async {
    // Query all tables in parallel, filtering out tombstoned rows.
    final results = await Future.wait([
      (_db.select(_db.driftConcepts)
            ..where((t) => t.isDeleted.equals(false)))
          .get(), // 0
      (_db.select(_db.driftRelationships)
            ..where((t) => t.isDeleted.equals(false)))
          .get(), // 1
      (_db.select(_db.driftQuizItems)
            ..where((t) => t.isDeleted.equals(false)))
          .get(), // 2
      (_db.select(_db.driftDocuments)
            ..where((t) => t.isDeleted.equals(false)))
          .get(), // 3
      (_db.select(_db.driftTopics)
            ..where((t) => t.isDeleted.equals(false)))
          .get(), // 4
      (_db.select(_db.driftTopicDocuments)
            ..where((t) => t.isDeleted.equals(false)))
          .get(), // 5
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
      // TODO(#41): Replace DELETE ALL with upsert + orphan tombstoning in PR 3.
      // Currently this wipes tombstones — acceptable while save() is the only
      // write path, but must change before changeset sync is enabled.
      await Future.wait([
        _db.delete(_db.driftTopicDocuments).go(),
        _db.delete(_db.driftTopics).go(),
        _db.delete(_db.driftDocuments).go(),
        _db.delete(_db.driftQuizItems).go(),
        _db.delete(_db.driftRelationships).go(),
        _db.delete(_db.driftConcepts).go(),
      ]);

      // 2. Batch-insert all entities. Uses insertOrReplace as a safety net
      //    in case the model layer has duplicate IDs (e.g. cross-document
      //    concept reuse during extraction). Each row is stamped with an
      //    HLC timestamp for CRDT sync.
      //
      // A single HLC is used for the entire batch — intentional. All rows
      // in an atomic save share the same causal timestamp, which is correct
      // for CRDT semantics (one logical event = one HLC).
      final hlc = _stampHlc();
      await _db.batch((batch) {
        batch.insertAll(
          _db.driftConcepts,
          graph.concepts.map((c) => c.toCompanion(hlc: hlc)).toList(),
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          _db.driftRelationships,
          graph.relationships.map((r) => r.toCompanion(hlc: hlc)).toList(),
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          _db.driftQuizItems,
          graph.quizItems.map((q) => q.toCompanion(hlc: hlc)).toList(),
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          _db.driftDocuments,
          graph.documentMetadata.map((d) => d.toCompanion(hlc: hlc)).toList(),
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          _db.driftTopics,
          graph.topics.map((t) => t.toCompanion(hlc: hlc)).toList(),
          mode: InsertMode.insertOrReplace,
        );

        // Flatten topic → document join rows.
        for (final topic in graph.topics) {
          for (final docId in topic.documentIds) {
            batch.insert(
              _db.driftTopicDocuments,
              DriftTopicDocumentsCompanion.insert(
                topicId: topic.id,
                documentId: docId,
                hlc: Value(hlc),
              ),
              mode: InsertMode.insertOrReplace,
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
        .insertOnConflictUpdate(item.toCompanion(hlc: _stampHlc()));
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
    final hlc = _stampHlc();
    await _db.batch((batch) {
      batch.insertAll(
        _db.driftConcepts,
        concepts.map((c) => c.toCompanion(hlc: hlc)).toList(),
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        _db.driftRelationships,
        relationships.map((r) => r.toCompanion(hlc: hlc)).toList(),
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        _db.driftQuizItems,
        quizItems.map((q) => q.toCompanion(hlc: hlc)).toList(),
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
