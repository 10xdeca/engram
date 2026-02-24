import '../models/concept.dart';
import '../models/knowledge_graph.dart';
import '../models/quiz_item.dart';
import '../models/relationship.dart';

/// Abstract storage interface for the knowledge graph.
///
/// Implementations:
/// - [DriftGraphRepository] — local SQLite via Drift (primary store)
/// - [FirestoreGraphRepository] — cloud Firestore
/// - [DualWriteGraphRepository] — reads from Drift, writes to both
/// - [LocalGraphRepository] — legacy JSON file (deprecated)
abstract class GraphRepository {
  Future<KnowledgeGraph> load();

  /// Persist [graph], upserting all entities and removing orphans.
  Future<void> save(KnowledgeGraph graph);

  /// Update a single quiz item. Local impl delegates to [save];
  /// Firestore impl writes a single subcollection document.
  Future<void> updateQuizItem(KnowledgeGraph graph, QuizItem item) async {
    await save(graph);
  }

  /// Additive save for split operations — writes only the new entities.
  /// Local impl delegates to [save]; Firestore impl writes individual docs.
  Future<void> saveSplitData({
    required KnowledgeGraph graph,
    required List<Concept> concepts,
    required List<Relationship> relationships,
    required List<QuizItem> quizItems,
  }) async {
    await save(graph);
  }

  /// Reactive stream of graph changes. Local impl emits once on load;
  /// Firestore impl emits on every snapshot change.
  Stream<KnowledgeGraph> watch();
}
