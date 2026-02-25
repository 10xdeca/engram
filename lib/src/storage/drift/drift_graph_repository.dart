import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart';

import '../../crdt/graph_changeset.dart';
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
/// **Warning:** [save] tombstones every active row not in the incoming
/// graph. The sync transport layer (Phase 5) should use [mergeChangeset]
/// for incoming remote data — never [save] with a partial graph, or it
/// will tombstone data from other devices.
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

  // -------------------------------------------------------------------------
  // getChangeset — extract modified rows since an HLC
  // -------------------------------------------------------------------------

  /// Returns all rows modified after [modifiedAfter] across all tables.
  ///
  /// Includes tombstoned rows (`isDeleted = true`) so that deletions
  /// propagate to other replicas. Pass an empty string to get the full
  /// state (every row in the database).
  ///
  /// Works because HLC strings are lexicographically ordered (ISO 8601
  /// date prefix + zero-padded hex counter), so `WHERE hlc > ?` is a
  /// simple string comparison in SQLite, accelerated by the `idx_*_hlc`
  /// indexes added in schema v3.
  Future<GraphChangeset> getChangeset({required String modifiedAfter}) async {
    final results = await Future.wait([
      (_db.select(_db.driftConcepts)
            ..where((t) => t.hlc.isBiggerThanValue(modifiedAfter)))
          .get(),
      (_db.select(_db.driftRelationships)
            ..where((t) => t.hlc.isBiggerThanValue(modifiedAfter)))
          .get(),
      (_db.select(_db.driftQuizItems)
            ..where((t) => t.hlc.isBiggerThanValue(modifiedAfter)))
          .get(),
      (_db.select(_db.driftDocuments)
            ..where((t) => t.hlc.isBiggerThanValue(modifiedAfter)))
          .get(),
      (_db.select(_db.driftTopics)
            ..where((t) => t.hlc.isBiggerThanValue(modifiedAfter)))
          .get(),
      (_db.select(_db.driftTopicDocuments)
            ..where((t) => t.hlc.isBiggerThanValue(modifiedAfter)))
          .get(),
    ]);

    return GraphChangeset(
      concepts: results[0] as List<DriftConcept>,
      relationships: results[1] as List<DriftRelationship>,
      quizItems: results[2] as List<DriftQuizItem>,
      documents: results[3] as List<DriftDocument>,
      topics: results[4] as List<DriftTopic>,
      topicDocuments: results[5] as List<DriftTopicDocument>,
    );
  }

  // -------------------------------------------------------------------------
  // mergeChangeset — apply incoming rows using LWW per HLC
  // -------------------------------------------------------------------------

  /// Merges an incoming changeset using last-write-wins (LWW) per HLC.
  ///
  /// For each incoming row:
  /// 1. Calls `receive(incoming.hlc)` on the [HlcManager] to advance the
  ///    local clock (ensures subsequent local writes have causal ordering).
  /// 2. Looks up the existing row by primary key.
  /// 3. If no existing row exists, or the incoming HLC is newer: upsert.
  /// 4. If the incoming HLC is older or equal: skip (idempotent).
  ///
  /// Incoming HLCs are **preserved** (not re-stamped) — this is what makes
  /// merge idempotent. The entire operation runs in a transaction so
  /// [watch] listeners see a single atomic update.
  ///
  /// Returns the number of rows actually written (newer or new rows).
  ///
  /// **Performance note:** Currently uses per-row SELECT-then-upsert (N+1
  /// pattern). At the expected scale (hundreds of rows per sync) this is
  /// acceptable since each SELECT hits the primary key index. For large
  /// changesets (1000+ rows), consider batch-SELECTing existing HLCs via
  /// `WHERE id IN (...)`, comparing in Dart, then batch-INSERTing winners.
  // TODO(perf): batch SELECT existing HLCs to avoid N+1 pattern
  Future<int> mergeChangeset(GraphChangeset changeset) async {
    if (changeset.isEmpty) return 0;
    final hlcManager = _hlcManager;
    if (hlcManager == null) {
      throw StateError('mergeChangeset requires an HlcManager');
    }

    var written = 0;

    await _db.transaction(() async {
      // -- Concepts --
      for (final incoming in changeset.concepts) {
        if (_isSameNode(incoming.hlc, hlcManager)) continue;
        _receiveHlc(incoming.hlc, hlcManager);
        final existing = await (_db.select(_db.driftConcepts)
              ..where((t) => t.id.equals(incoming.id)))
            .getSingleOrNull();
        if (existing == null || incoming.hlc.compareTo(existing.hlc) > 0) {
          await _db
              .into(_db.driftConcepts)
              .insertOnConflictUpdate(incoming.toInsertCompanion());
          written++;
        }
      }

      // -- Relationships --
      for (final incoming in changeset.relationships) {
        if (_isSameNode(incoming.hlc, hlcManager)) continue;
        _receiveHlc(incoming.hlc, hlcManager);
        final existing = await (_db.select(_db.driftRelationships)
              ..where((t) => t.id.equals(incoming.id)))
            .getSingleOrNull();
        if (existing == null || incoming.hlc.compareTo(existing.hlc) > 0) {
          await _db
              .into(_db.driftRelationships)
              .insertOnConflictUpdate(incoming.toInsertCompanion());
          written++;
        }
      }

      // -- Quiz items --
      for (final incoming in changeset.quizItems) {
        if (_isSameNode(incoming.hlc, hlcManager)) continue;
        _receiveHlc(incoming.hlc, hlcManager);
        final existing = await (_db.select(_db.driftQuizItems)
              ..where((t) => t.id.equals(incoming.id)))
            .getSingleOrNull();
        if (existing == null || incoming.hlc.compareTo(existing.hlc) > 0) {
          await _db
              .into(_db.driftQuizItems)
              .insertOnConflictUpdate(incoming.toInsertCompanion());
          written++;
        }
      }

      // -- Documents (PK is documentId) --
      for (final incoming in changeset.documents) {
        if (_isSameNode(incoming.hlc, hlcManager)) continue;
        _receiveHlc(incoming.hlc, hlcManager);
        final existing = await (_db.select(_db.driftDocuments)
              ..where((t) => t.documentId.equals(incoming.documentId)))
            .getSingleOrNull();
        if (existing == null || incoming.hlc.compareTo(existing.hlc) > 0) {
          await _db
              .into(_db.driftDocuments)
              .insertOnConflictUpdate(incoming.toInsertCompanion());
          written++;
        }
      }

      // -- Topics --
      for (final incoming in changeset.topics) {
        if (_isSameNode(incoming.hlc, hlcManager)) continue;
        _receiveHlc(incoming.hlc, hlcManager);
        final existing = await (_db.select(_db.driftTopics)
              ..where((t) => t.id.equals(incoming.id)))
            .getSingleOrNull();
        if (existing == null || incoming.hlc.compareTo(existing.hlc) > 0) {
          await _db
              .into(_db.driftTopics)
              .insertOnConflictUpdate(incoming.toInsertCompanion());
          written++;
        }
      }

      // -- Topic documents (composite PK: topicId + documentId) --
      for (final incoming in changeset.topicDocuments) {
        if (_isSameNode(incoming.hlc, hlcManager)) continue;
        _receiveHlc(incoming.hlc, hlcManager);
        final existing = await (_db.select(_db.driftTopicDocuments)
              ..where(
                (t) =>
                    t.topicId.equals(incoming.topicId) &
                    t.documentId.equals(incoming.documentId),
              ))
            .getSingleOrNull();
        if (existing == null || incoming.hlc.compareTo(existing.hlc) > 0) {
          await _db
              .into(_db.driftTopicDocuments)
              .insertOnConflictUpdate(incoming.toInsertCompanion());
          written++;
        }
      }
    });

    return written;
  }

  /// Guards against merging our own HLCs back (would cause
  /// `DuplicateNodeException` in `Hlc.merge()`).
  bool _isSameNode(String hlcString, HlcManager hlcManager) {
    if (hlcString.isEmpty) return false;
    return hlcString.endsWith(hlcManager.nodeId);
  }

  /// Advances the local HLC by receiving a remote HLC string.
  void _receiveHlc(String hlcString, HlcManager hlcManager) {
    if (hlcString.isEmpty) return;
    hlcManager.receive(Hlc.parse(hlcString));
  }

  // -------------------------------------------------------------------------
  // getLastModified — highest HLC across all tables
  // -------------------------------------------------------------------------

  /// Returns the highest HLC across all tables, or empty string if the
  /// database is empty.
  ///
  /// Useful for "sync since last known state" bookkeeping — pass the
  /// result to [getChangeset] on the remote peer.
  Future<String> getLastModified() async {
    final results = await Future.wait([
      _maxHlc('drift_concepts'),
      _maxHlc('drift_relationships'),
      _maxHlc('drift_quiz_items'),
      _maxHlc('drift_documents'),
      _maxHlc('drift_topics'),
      _maxHlc('drift_topic_documents'),
    ]);

    return results.fold<String>('', (best, hlc) {
      if (hlc.isEmpty) return best;
      if (best.isEmpty) return hlc;
      return hlc.compareTo(best) > 0 ? hlc : best;
    });
  }

  /// Returns `MAX(hlc)` for a single table, or empty string if the table
  /// is empty. Uses a raw query since Drift's `max()` aggregate isn't
  /// available on non-query builders.
  Future<String> _maxHlc(String tableName) async {
    final result = await _db.customSelect(
      'SELECT MAX(hlc) AS max_hlc FROM $tableName',
    ).getSingle();
    return (result.data['max_hlc'] as String?) ?? '';
  }
}
