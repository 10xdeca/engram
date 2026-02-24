import 'dart:async';

import 'package:drift/native.dart';
import 'package:engram/src/models/concept.dart';
import 'package:engram/src/models/document_metadata.dart';
import 'package:engram/src/models/knowledge_graph.dart';
import 'package:engram/src/models/relationship.dart';
import 'package:engram/src/models/topic.dart';
import 'package:engram/src/storage/drift/drift_graph_repository.dart';
import 'package:engram/src/storage/drift/engram_database.dart';
import 'package:test/test.dart';

import '../../helpers/quiz_item_helpers.dart';

void main() {
  late EngramDatabase db;
  late DriftGraphRepository repo;

  setUp(() {
    db = EngramDatabase.forTesting(NativeDatabase.memory());
    repo = DriftGraphRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // Test fixtures
  // ---------------------------------------------------------------------------

  /// Builds a realistic graph with all entity types populated.
  KnowledgeGraph fullGraph() {
    return KnowledgeGraph(
      concepts: [
        Concept(
          id: 'c1',
          name: 'Docker',
          description: 'Container runtime',
          sourceDocumentId: 'doc1',
          tags: const ['devops', 'containers'],
        ),
        Concept(
          id: 'c2',
          name: 'Kubernetes',
          description: 'Container orchestration',
          sourceDocumentId: 'doc1',
          parentConceptId: 'c1',
        ),
      ],
      relationships: const [
        Relationship(
          id: 'r1',
          fromConceptId: 'c2',
          toConceptId: 'c1',
          label: 'depends on',
          description: 'K8s requires Docker or similar runtime',
          type: RelationshipType.prerequisite,
        ),
      ],
      quizItems: [
        testQuizItem(
          id: 'q1',
          conceptId: 'c1',
          question: 'What is Docker?',
          answer: 'A container runtime',
          difficulty: 4.2,
          stability: 12.5,
          fsrsState: 2,
          lapses: 1,
          predictedDifficulty: 3.8,
          reviewCount: 7,
        ),
        testQuizItem(
          id: 'q2',
          conceptId: 'c2',
          question: 'What is a Pod?',
          answer: 'Smallest K8s unit',
        ),
      ],
      documentMetadata: [
        DocumentMetadata(
          documentId: 'doc1',
          title: 'Container Basics',
          updatedAt: '2026-02-20T10:00:00.000Z',
          ingestedAt: DateTime.utc(2026, 2, 24),
          collectionId: 'col1',
          collectionName: 'DevOps',
          ingestedText: 'Docker is a container runtime...',
        ),
      ],
      topics: [
        Topic(
          id: 't1',
          name: 'Containers',
          description: 'Docker and K8s',
          documentIds: const {'doc1'},
          createdAt: DateTime.utc(2026, 1, 15),
          lastIngestedAt: DateTime.utc(2026, 2, 20),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // load
  // ---------------------------------------------------------------------------

  group('load', () {
    test('returns empty graph when DB is empty', () async {
      final graph = await repo.load();

      expect(graph.concepts, isEmpty);
      expect(graph.relationships, isEmpty);
      expect(graph.quizItems, isEmpty);
      expect(graph.documentMetadata, isEmpty);
      expect(graph.topics, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // save + load round-trip
  // ---------------------------------------------------------------------------

  group('save + load', () {
    test('round-trips full KnowledgeGraph', () async {
      final original = fullGraph();

      await repo.save(original);
      final loaded = await repo.load();

      expect(loaded.concepts.length, original.concepts.length);
      expect(loaded.relationships.length, original.relationships.length);
      expect(loaded.quizItems.length, original.quizItems.length);
      expect(loaded.documentMetadata.length, original.documentMetadata.length);
      expect(loaded.topics.length, original.topics.length);

      // Verify content
      final c1 = loaded.concepts.firstWhere((c) => c.id == 'c1');
      expect(c1.name, 'Docker');
      expect(c1.tags.toList(), ['devops', 'containers']);
      expect(c1.parentConceptId, isNull);

      final c2 = loaded.concepts.firstWhere((c) => c.id == 'c2');
      expect(c2.parentConceptId, 'c1');

      final r1 = loaded.relationships.first;
      expect(r1.type, RelationshipType.prerequisite);
      expect(r1.description, 'K8s requires Docker or similar runtime');

      final q1 = loaded.quizItems.firstWhere((q) => q.id == 'q1');
      expect(q1.difficulty, 4.2);
      expect(q1.stability, 12.5);
      expect(q1.fsrsState, 2);
      expect(q1.lapses, 1);
      expect(q1.predictedDifficulty, 3.8);
      expect(q1.reviewCount, 7);

      final doc = loaded.documentMetadata.first;
      expect(doc.collectionId, 'col1');
      expect(doc.ingestedText, 'Docker is a container runtime...');

      final topic = loaded.topics.first;
      expect(topic.documentIds.length, 1);
      expect(topic.documentIds.contains('doc1'), isTrue);
      expect(topic.lastIngestedAt, DateTime.utc(2026, 2, 20));
    });

    test('replaces all data atomically (save A, save B, only B exists)',
        () async {
      final graphA = fullGraph();
      await repo.save(graphA);

      // Save a completely different graph
      final graphB = KnowledgeGraph(
        concepts: [
          Concept(
            id: 'cx',
            name: 'Rust',
            description: 'Systems language',
            sourceDocumentId: 'docX',
          ),
        ],
      );
      await repo.save(graphB);

      final loaded = await repo.load();

      // Only graph B data should exist
      expect(loaded.concepts.length, 1);
      expect(loaded.concepts.first.id, 'cx');
      expect(loaded.relationships, isEmpty);
      expect(loaded.quizItems, isEmpty);
      expect(loaded.documentMetadata, isEmpty);
      expect(loaded.topics, isEmpty);
    });

    test('handles empty graph', () async {
      // Save non-empty first
      await repo.save(fullGraph());

      // Overwrite with empty
      await repo.save(KnowledgeGraph());

      final loaded = await repo.load();
      expect(loaded.concepts, isEmpty);
      expect(loaded.relationships, isEmpty);
      expect(loaded.quizItems, isEmpty);
      expect(loaded.documentMetadata, isEmpty);
      expect(loaded.topics, isEmpty);
    });

    test('normalizes topic documentIds into join table', () async {
      final graph = KnowledgeGraph(
        topics: [
          Topic(
            id: 't1',
            name: 'Multi-doc topic',
            documentIds: const {'doc1', 'doc2', 'doc3'},
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      await repo.save(graph);
      final loaded = await repo.load();

      final topic = loaded.topics.first;
      expect(topic.documentIds.length, 3);
      expect(topic.documentIds, containsAll(['doc1', 'doc2', 'doc3']));
    });
  });

  // ---------------------------------------------------------------------------
  // updateQuizItem
  // ---------------------------------------------------------------------------

  group('updateQuizItem', () {
    test('writes single row, others unchanged', () async {
      final graph = fullGraph();
      await repo.save(graph);

      // Update q1 with new FSRS state
      final updatedItem = testQuizItem(
        id: 'q1',
        conceptId: 'c1',
        question: 'What is Docker?',
        answer: 'A container runtime',
        difficulty: 6.0,
        stability: 20.0,
        fsrsState: 2,
        lapses: 2,
        reviewCount: 8,
        nextReview: DateTime.utc(2026, 3, 15),
        lastReview: DateTime.utc(2026, 2, 24),
      );

      await repo.updateQuizItem(graph, updatedItem);
      final loaded = await repo.load();

      // Updated item should have new values
      final q1 = loaded.quizItems.firstWhere((q) => q.id == 'q1');
      expect(q1.difficulty, 6.0);
      expect(q1.stability, 20.0);
      expect(q1.lapses, 2);
      expect(q1.reviewCount, 8);

      // Other quiz item should be unchanged
      final q2 = loaded.quizItems.firstWhere((q) => q.id == 'q2');
      expect(q2.question, 'What is a Pod?');

      // Other entities should be unchanged
      expect(loaded.concepts.length, 2);
      expect(loaded.relationships.length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // saveSplitData
  // ---------------------------------------------------------------------------

  group('saveSplitData', () {
    test('is additive — originals and new coexist', () async {
      final graph = fullGraph();
      await repo.save(graph);

      // Split c1 into sub-concepts
      final newConcepts = [
        Concept(
          id: 'c1-sub1',
          name: 'Docker Images',
          description: 'Immutable app snapshots',
          sourceDocumentId: 'doc1',
          parentConceptId: 'c1',
        ),
        Concept(
          id: 'c1-sub2',
          name: 'Docker Containers',
          description: 'Running image instances',
          sourceDocumentId: 'doc1',
          parentConceptId: 'c1',
        ),
      ];

      const newRelationships = [
        Relationship(
          id: 'r-split1',
          fromConceptId: 'c1-sub1',
          toConceptId: 'c1',
          label: 'is part of',
          type: RelationshipType.composition,
        ),
        Relationship(
          id: 'r-split2',
          fromConceptId: 'c1-sub2',
          toConceptId: 'c1',
          label: 'is part of',
          type: RelationshipType.composition,
        ),
      ];

      final newQuizItems = [
        testQuizItem(
          id: 'q-sub1',
          conceptId: 'c1-sub1',
          question: 'What is a Docker image?',
          answer: 'An immutable snapshot',
        ),
        testQuizItem(
          id: 'q-sub2',
          conceptId: 'c1-sub2',
          question: 'What is a Docker container?',
          answer: 'A running image instance',
        ),
      ];

      await repo.saveSplitData(
        graph: graph,
        concepts: newConcepts,
        relationships: newRelationships,
        quizItems: newQuizItems,
      );

      final loaded = await repo.load();

      // Original + new
      expect(loaded.concepts.length, 4); // c1, c2, c1-sub1, c1-sub2
      expect(loaded.relationships.length, 3); // r1, r-split1, r-split2
      expect(loaded.quizItems.length, 4); // q1, q2, q-sub1, q-sub2

      // Original concept still exists
      expect(loaded.concepts.any((c) => c.id == 'c1'), isTrue);

      // New sub-concepts have correct parentConceptId
      final sub1 = loaded.concepts.firstWhere((c) => c.id == 'c1-sub1');
      expect(sub1.parentConceptId, 'c1');
    });
  });

  // ---------------------------------------------------------------------------
  // watch
  // ---------------------------------------------------------------------------

  group('watch', () {
    test('emits initial state then reacts to changes', () async {
      await repo.save(fullGraph());

      final emissions = <KnowledgeGraph>[];
      final completer = Completer<void>();
      var count = 0;

      final subscription = repo.watch().listen((graph) {
        emissions.add(graph);
        count++;
        // Expect 2 emissions: initial + after save
        if (count >= 2) completer.complete();
      });

      // Wait for initial emission
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.length, 1);
      expect(emissions.first.concepts.length, 2);

      // Trigger a change
      await repo.save(KnowledgeGraph(
        concepts: [
          Concept(
            id: 'cx',
            name: 'Rust',
            description: 'Systems language',
            sourceDocumentId: 'docX',
          ),
        ],
      ));

      // Wait for the second emission
      await completer.future.timeout(const Duration(seconds: 5));

      expect(emissions.length, greaterThanOrEqualTo(2));
      final last = emissions.last;
      expect(last.concepts.length, 1);
      expect(last.concepts.first.id, 'cx');

      await subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // FSRS state
  // ---------------------------------------------------------------------------

  group('FSRS state', () {
    test('full FSRS state survives round-trip', () async {
      final mastered = masteredQuizItem(
        id: 'qm',
        conceptId: 'c1',
        predictedDifficulty: 6.5,
        reviewCount: 12,
      );

      final graph = KnowledgeGraph(
        concepts: [
          Concept(
            id: 'c1',
            name: 'Test',
            description: 'Test',
            sourceDocumentId: 'doc1',
          ),
        ],
        quizItems: [mastered],
      );

      await repo.save(graph);
      final loaded = await repo.load();

      final item = loaded.quizItems.first;
      expect(item.isFsrs, isTrue);
      expect(item.isMasteredForUnlock, isTrue);
      expect(item.difficulty, 5.0);
      expect(item.stability, 25.0);
      expect(item.fsrsState, 2);
      expect(item.lapses, 0);
      expect(item.predictedDifficulty, 6.5);
      expect(item.reviewCount, 12);
      expect(item.lastReview, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Topic document aggregation
  // ---------------------------------------------------------------------------

  group('topic document aggregation', () {
    test('multiple topics with shared documents aggregate correctly', () async {
      final graph = KnowledgeGraph(
        documentMetadata: [
          DocumentMetadata(
            documentId: 'doc1',
            title: 'Doc 1',
            updatedAt: '2026-01-01',
            ingestedAt: DateTime.utc(2026, 1, 1),
          ),
          DocumentMetadata(
            documentId: 'doc2',
            title: 'Doc 2',
            updatedAt: '2026-01-02',
            ingestedAt: DateTime.utc(2026, 1, 2),
          ),
          DocumentMetadata(
            documentId: 'doc3',
            title: 'Doc 3',
            updatedAt: '2026-01-03',
            ingestedAt: DateTime.utc(2026, 1, 3),
          ),
        ],
        topics: [
          Topic(
            id: 't1',
            name: 'Topic A',
            documentIds: const {'doc1', 'doc2'},
            createdAt: DateTime.utc(2026, 1, 1),
          ),
          Topic(
            id: 't2',
            name: 'Topic B',
            documentIds: const {'doc2', 'doc3'},
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      await repo.save(graph);
      final loaded = await repo.load();

      final topicA = loaded.topics.firstWhere((t) => t.id == 't1');
      final topicB = loaded.topics.firstWhere((t) => t.id == 't2');

      // Each topic gets its own document set
      expect(topicA.documentIds, containsAll(['doc1', 'doc2']));
      expect(topicA.documentIds.length, 2);

      expect(topicB.documentIds, containsAll(['doc2', 'doc3']));
      expect(topicB.documentIds.length, 2);

      // doc2 is shared but each topic independently tracks it
      expect(topicA.documentIds.contains('doc2'), isTrue);
      expect(topicB.documentIds.contains('doc2'), isTrue);
    });
  });
}
