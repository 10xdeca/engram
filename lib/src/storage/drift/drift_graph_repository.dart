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
/// atomic updates. The [save] method uses **upsert + orphan tombstoning**:
/// incoming entities are upserted (INSERT OR REPLACE), and active rows
/// not present in the incoming graph are soft-deleted (`isDeleted = true`)
/// rather than physically removed. This preserves tombstones for CRDT
/// changeset propagation (#41).
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
  // save — upsert + orphan tombstoning inside a transaction
  // -------------------------------------------------------------------------

  @override
  Future<void> save(KnowledgeGraph graph) async {
    await _db.transaction(() async {
      // A single HLC is used for the entire save — intentional. All rows
      // in an atomic save share the same causal timestamp, which is correct
      // for CRDT semantics (one logical event = one HLC).
      final hlc = _stampHlc();

      // 1. Upsert all incoming entities. Uses insertOrReplace as a safety
      //    net for duplicate IDs (e.g. cross-document concept reuse during
      //    extraction). This also resurrects any previously tombstoned rows
      //    because INSERT OR REPLACE resets isDeleted to its default (false).
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

      // 2. Tombstone orphans — active rows not present in the incoming
      //    graph. These rows are soft-deleted (isDeleted = true) rather
      //    than physically removed, preserving them for CRDT changeset
      //    propagation. Drift's isNotIn([]) returns Constant(true), so
      //    when a table has no incoming entities all active rows are
      //    tombstoned — matching the old DELETE ALL semantics from load()'s
      //    perspective while keeping the rows for sync.
      await _tombstoneOrphans(graph, hlc);
    });
  }

  /// Tombstones active rows that are absent from [graph].
  ///
  /// For single-PK tables (concepts, relationships, quiz items, documents,
  /// topics), uses `WHERE isDeleted = false AND id NOT IN (...)`. For the
  /// composite-PK topic-document join table, queries existing pairs and
  /// tombstones those not in the incoming set.
  Future<void> _tombstoneOrphans(KnowledgeGraph graph, String hlc) async {
    // -- Concepts --
    await (_db.update(_db.driftConcepts)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.id.isNotIn(graph.concepts.map((c) => c.id)),
          ))
        .write(DriftConceptsCompanion(
          isDeleted: const Value(true),
          hlc: Value(hlc),
        ));

    // -- Relationships --
    await (_db.update(_db.driftRelationships)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.id.isNotIn(graph.relationships.map((r) => r.id)),
          ))
        .write(DriftRelationshipsCompanion(
          isDeleted: const Value(true),
          hlc: Value(hlc),
        ));

    // -- Quiz items --
    await (_db.update(_db.driftQuizItems)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.id.isNotIn(graph.quizItems.map((q) => q.id)),
          ))
        .write(DriftQuizItemsCompanion(
          isDeleted: const Value(true),
          hlc: Value(hlc),
        ));

    // -- Documents (PK is documentId, not id) --
    await (_db.update(_db.driftDocuments)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.documentId.isNotIn(
                  graph.documentMetadata.map((d) => d.documentId),
                ),
          ))
        .write(DriftDocumentsCompanion(
          isDeleted: const Value(true),
          hlc: Value(hlc),
        ));

    // -- Topics --
    await (_db.update(_db.driftTopics)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.id.isNotIn(graph.topics.map((t) => t.id)),
          ))
        .write(DriftTopicsCompanion(
          isDeleted: const Value(true),
          hlc: Value(hlc),
        ));

    // -- Topic documents (composite PK: topicId + documentId) --
    await _tombstoneOrphanTopicDocuments(graph, hlc);
  }

  /// Tombstones orphan topic-document join rows.
  ///
  /// The composite `(topicId, documentId)` primary key can't use a simple
  /// Drift `isNotIn(...)` on a single column. Instead, we concatenate the
  /// key columns with a `|` separator and use a single `NOT IN (...)` via
  /// [customUpdate]. This is O(1) SQL round-trips regardless of the number
  /// of orphan pairs — more efficient than per-row updates.
  Future<void> _tombstoneOrphanTopicDocuments(
    KnowledgeGraph graph,
    String hlc,
  ) async {
    // Build set of incoming composite keys (pipe-delimited).
    final incomingKeys = <String>[];
    for (final topic in graph.topics) {
      for (final docId in topic.documentIds) {
        incomingKeys.add('${topic.id}|$docId');
      }
    }

    if (incomingKeys.isEmpty) {
      // No incoming pairs — tombstone all active rows.
      await (_db.update(_db.driftTopicDocuments)
            ..where((t) => t.isDeleted.equals(false)))
          .write(DriftTopicDocumentsCompanion(
            isDeleted: const Value(true),
            hlc: Value(hlc),
          ));
      return;
    }

    // Single SQL statement: concatenate key columns and use NOT IN.
    final placeholders = List.filled(incomingKeys.length, '?').join(', ');
    await _db.customUpdate(
      'UPDATE drift_topic_documents '
      "SET is_deleted = 1, hlc = ? "
      'WHERE is_deleted = 0 '
      "AND (topic_id || '|' || document_id) NOT IN ($placeholders)",
      variables: [
        Variable<String>(hlc),
        ...incomingKeys.map((k) => Variable<String>(k)),
      ],
      updates: {_db.driftTopicDocuments},
    );
  }

  // -------------------------------------------------------------------------
  // purgeTombstones — physical deletion for sync cleanup
  // -------------------------------------------------------------------------

  /// Physically removes tombstoned rows with `hlc < [before]`.
  ///
  /// Called by the sync layer after confirming all replicas have received
  /// the tombstones. This prevents unbounded tombstone growth. Safe to call
  /// at any time — only affects rows that are already soft-deleted and
  /// whose HLC timestamp is strictly less than the threshold.
  ///
  /// Returns the total number of rows purged across all tables.
  Future<int> purgeTombstones({required String before}) async {
    var count = 0;
    await _db.transaction(() async {
      count += await (_db.delete(_db.driftTopicDocuments)
            ..where(
              (t) =>
                  t.isDeleted.equals(true) &
                  t.hlc.isSmallerThanValue(before),
            ))
          .go();
      count += await (_db.delete(_db.driftTopics)
            ..where(
              (t) =>
                  t.isDeleted.equals(true) &
                  t.hlc.isSmallerThanValue(before),
            ))
          .go();
      count += await (_db.delete(_db.driftDocuments)
            ..where(
              (t) =>
                  t.isDeleted.equals(true) &
                  t.hlc.isSmallerThanValue(before),
            ))
          .go();
      count += await (_db.delete(_db.driftQuizItems)
            ..where(
              (t) =>
                  t.isDeleted.equals(true) &
                  t.hlc.isSmallerThanValue(before),
            ))
          .go();
      count += await (_db.delete(_db.driftRelationships)
            ..where(
              (t) =>
                  t.isDeleted.equals(true) &
                  t.hlc.isSmallerThanValue(before),
            ))
          .go();
      count += await (_db.delete(_db.driftConcepts)
            ..where(
              (t) =>
                  t.isDeleted.equals(true) &
                  t.hlc.isSmallerThanValue(before),
            ))
          .go();
    });
    return count;
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
