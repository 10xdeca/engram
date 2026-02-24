import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/concept.dart';
import '../models/knowledge_graph.dart';
import '../models/quiz_item.dart';
import '../models/relationship.dart';
import 'graph_repository.dart';

/// [GraphRepository] that writes to a local primary store and a remote
/// secondary store, implementing the dual-write bridge for the local-first
/// migration (#40).
///
/// **Reads** always come from [primary] (fast, offline-capable).
/// **Writes** go to [primary] first (awaited), then to [remote]
/// fire-and-forget. If [remote] fails, the error is logged but not
/// propagated — the local write has already succeeded.
///
/// On the first [load], if [primary] is empty, data is seeded from [remote]
/// (one-time migration). The [_seeded] flag prevents redundant remote loads.
///
/// **Phase 2 (CRDT sync):** This class is the natural place to add conflict
/// resolution hooks when Firestore transitions from fire-and-forget writes
/// to a proper sync peer. See `docs/CRDT_SYNC_ARCHITECTURE.md`.
class DualWriteGraphRepository extends GraphRepository {
  DualWriteGraphRepository({
    required this.primary,
    required this.remote,
  });

  /// Local store (Drift/SQLite) — source of truth for reads.
  @visibleForTesting
  final GraphRepository primary;

  /// Remote store (Firestore) — secondary write target.
  @visibleForTesting
  final GraphRepository remote;

  /// Whether the initial seed check has been performed.
  ///
  /// Intentionally instance-scoped: when the provider rebuilds (e.g. sign-out
  /// then sign-in as a different user), a fresh instance gets `seeded = false`
  /// so the new user's Firestore data can be seeded into Drift.
  @visibleForTesting
  bool seeded = false;

  // ---------------------------------------------------------------------------
  // load — read from primary; seed from remote on first call if empty
  // ---------------------------------------------------------------------------

  @override
  Future<KnowledgeGraph> load() async {
    final localGraph = await primary.load();

    if (!seeded) {
      seeded = true;

      if (_isEmpty(localGraph)) {
        try {
          final remoteGraph = await remote.load();
          if (!_isEmpty(remoteGraph)) {
            await primary.save(remoteGraph);
            return remoteGraph;
          }
        } on Exception catch (e) {
          debugPrint('[DualWrite] seed from remote failed: $e');
        }
      }
    }

    return localGraph;
  }

  // ---------------------------------------------------------------------------
  // save — primary (awaited) + remote (fire-and-forget)
  // ---------------------------------------------------------------------------

  @override
  Future<void> save(KnowledgeGraph graph) async {
    await primary.save(graph);
    _fireAndForget(() => remote.save(graph), 'save');
  }

  // ---------------------------------------------------------------------------
  // updateQuizItem — primary (awaited) + remote (fire-and-forget)
  // ---------------------------------------------------------------------------

  @override
  Future<void> updateQuizItem(KnowledgeGraph graph, QuizItem item) async {
    await primary.updateQuizItem(graph, item);
    _fireAndForget(() => remote.updateQuizItem(graph, item), 'updateQuizItem');
  }

  // ---------------------------------------------------------------------------
  // saveSplitData — primary (awaited) + remote (fire-and-forget)
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveSplitData({
    required KnowledgeGraph graph,
    required List<Concept> concepts,
    required List<Relationship> relationships,
    required List<QuizItem> quizItems,
  }) async {
    await primary.saveSplitData(
      graph: graph,
      concepts: concepts,
      relationships: relationships,
      quizItems: quizItems,
    );
    _fireAndForget(
      () => remote.saveSplitData(
        graph: graph,
        concepts: concepts,
        relationships: relationships,
        quizItems: quizItems,
      ),
      'saveSplitData',
    );
  }

  // ---------------------------------------------------------------------------
  // watch — delegates to primary only
  // ---------------------------------------------------------------------------

  @override
  Stream<KnowledgeGraph> watch() => primary.watch();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` when [graph] has no entities at all.
  bool _isEmpty(KnowledgeGraph graph) =>
      graph.concepts.isEmpty &&
      graph.relationships.isEmpty &&
      graph.quizItems.isEmpty &&
      graph.documentMetadata.isEmpty;

  /// Executes [fn] without awaiting. Catches both synchronous throws and
  /// asynchronous errors, logging via [debugPrint].
  void _fireAndForget(Future<void> Function() fn, String operation) {
    try {
      unawaited(
        fn().catchError((Object e) {
          debugPrint('[DualWrite] remote $operation failed: $e');
        }),
      );
    } on Object catch (e) {
      debugPrint('[DualWrite] remote $operation failed: $e');
    }
  }
}
