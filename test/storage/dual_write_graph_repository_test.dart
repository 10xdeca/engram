import 'dart:async';

import 'package:drift/native.dart';
import 'package:engram/src/models/concept.dart';
import 'package:engram/src/models/document_metadata.dart';
import 'package:engram/src/models/knowledge_graph.dart';
import 'package:engram/src/models/quiz_item.dart';
import 'package:engram/src/models/relationship.dart';
import 'package:engram/src/storage/dual_write_graph_repository.dart';
import 'package:engram/src/storage/drift/drift_graph_repository.dart';
import 'package:engram/src/storage/drift/engram_database.dart';
import 'package:engram/src/storage/graph_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/quiz_item_helpers.dart';

class MockGraphRepository extends Mock implements GraphRepository {}

void main() {
  late EngramDatabase db;
  late DriftGraphRepository driftRepo;
  late MockGraphRepository mockRemote;
  late DualWriteGraphRepository dualRepo;

  setUpAll(() {
    registerFallbackValue(KnowledgeGraph.empty);
    registerFallbackValue(testQuizItem());
    registerFallbackValue(<Concept>[]);
    registerFallbackValue(<Relationship>[]);
    registerFallbackValue(<QuizItem>[]);
  });

  setUp(() {
    db = EngramDatabase.forTesting(NativeDatabase.memory());
    driftRepo = DriftGraphRepository(db: db);
    mockRemote = MockGraphRepository();
    dualRepo = DualWriteGraphRepository(
      primary: driftRepo,
      remote: mockRemote,
    );
  });

  tearDown(() async {
    await db.close();
  });

  // Stub remote.save/updateQuizItem/saveSplitData to succeed by default.
  void stubRemoteWritesSucceed() {
    when(() => mockRemote.save(any())).thenAnswer((_) async {});
    when(
      () => mockRemote.updateQuizItem(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockRemote.saveSplitData(
        graph: any(named: 'graph'),
        concepts: any(named: 'concepts'),
        relationships: any(named: 'relationships'),
        quizItems: any(named: 'quizItems'),
      ),
    ).thenAnswer((_) async {});
  }

  /// Builds a realistic graph for seeding / saving.
  KnowledgeGraph sampleGraph() {
    return KnowledgeGraph(
      concepts: [
        Concept(
          id: 'c1',
          name: 'Docker',
          description: 'Container runtime',
          sourceDocumentId: 'doc1',
        ),
        Concept(
          id: 'c2',
          name: 'Kubernetes',
          description: 'Container orchestration',
          sourceDocumentId: 'doc1',
        ),
      ],
      relationships: const [
        Relationship(
          id: 'r1',
          fromConceptId: 'c1',
          toConceptId: 'c2',
          label: 'used by',
          type: RelationshipType.prerequisite,
        ),
      ],
      quizItems: [
        testQuizItem(id: 'q1', conceptId: 'c1'),
      ],
      documentMetadata: [
        DocumentMetadata(
          documentId: 'doc1',
          title: 'Container Guide',
          updatedAt: '2026-01-01T00:00:00.000Z',
          ingestedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // load — empty state
  // ---------------------------------------------------------------------------

  group('load', () {
    test('returns empty when both repos are empty', () async {
      when(() => mockRemote.load()).thenAnswer(
        (_) async => KnowledgeGraph.empty,
      );

      final graph = await dualRepo.load();

      expect(graph.concepts, isEmpty);
      expect(graph.relationships, isEmpty);
      expect(graph.quizItems, isEmpty);
      expect(graph.documentMetadata, isEmpty);
    });

    // -------------------------------------------------------------------------
    // load — seeding
    // -------------------------------------------------------------------------

    test('seeds Drift from Firestore when Drift is empty', () async {
      final remoteGraph = sampleGraph();
      when(() => mockRemote.load()).thenAnswer((_) async => remoteGraph);
      stubRemoteWritesSucceed();

      final graph = await dualRepo.load();

      // Should return the seeded data.
      expect(graph.concepts.length, 2);
      expect(graph.relationships.length, 1);
      expect(graph.quizItems.length, 1);
      expect(graph.documentMetadata.length, 1);

      // Drift should now have the data persisted.
      final driftGraph = await driftRepo.load();
      expect(driftGraph.concepts.length, 2);
      expect(driftGraph.concepts.first.name, 'Docker');
    });

    test('does NOT seed when Drift already has data', () async {
      // Pre-populate Drift.
      await driftRepo.save(sampleGraph());

      // Remote has different data — should be ignored.
      when(() => mockRemote.load()).thenAnswer(
        (_) async => KnowledgeGraph(
          concepts: [
            Concept(
              id: 'cx',
              name: 'Rust',
              description: 'Systems language',
              sourceDocumentId: 'docX',
            ),
          ],
        ),
      );

      final graph = await dualRepo.load();

      // Should reflect Drift's data, not remote's.
      expect(graph.concepts.length, 2);
      expect(graph.concepts.any((c) => c.name == 'Docker'), isTrue);
      expect(graph.concepts.any((c) => c.name == 'Rust'), isFalse);

      // Remote.load() should NOT be called — Drift had data.
      verifyNever(() => mockRemote.load());
    });

    test('seeds only once — second load skips Firestore', () async {
      when(() => mockRemote.load()).thenAnswer(
        (_) async => sampleGraph(),
      );
      stubRemoteWritesSucceed();

      // First load — triggers seed.
      await dualRepo.load();
      verify(() => mockRemote.load()).called(1);

      // Second load — should NOT call remote again.
      final graph2 = await dualRepo.load();
      verifyNever(() => mockRemote.load());

      // Data should still be there from Drift.
      expect(graph2.concepts.length, 2);
    });

    test('handles Firestore seed failure gracefully', () async {
      when(() => mockRemote.load()).thenThrow(
        Exception('Network unavailable'),
      );

      final graph = await dualRepo.load();

      // Should return empty — no crash.
      expect(graph.concepts, isEmpty);
      // The failed seed attempt should have called remote.load() once.
      verify(() => mockRemote.load()).called(1);

      // The _seeded flag should be set so we don't retry next time.
      // Even though remote now has data, it should NOT be consulted.
      reset(mockRemote);
      when(() => mockRemote.load()).thenAnswer(
        (_) async => sampleGraph(),
      );
      final graph2 = await dualRepo.load();
      expect(graph2.concepts, isEmpty);
      verifyNever(() => mockRemote.load());
    });
  });

  // ---------------------------------------------------------------------------
  // save — dual write
  // ---------------------------------------------------------------------------

  group('save', () {
    test('writes to both Drift and Firestore', () async {
      stubRemoteWritesSucceed();
      // Mark as seeded so load doesn't interfere.
      when(() => mockRemote.load()).thenAnswer(
        (_) async => KnowledgeGraph.empty,
      );
      await dualRepo.load(); // sets _seeded = true

      final graph = sampleGraph();
      await dualRepo.save(graph);

      // Drift should have the data.
      final driftGraph = await driftRepo.load();
      expect(driftGraph.concepts.length, 2);

      // Remote should have been called.
      verify(() => mockRemote.save(graph)).called(1);
    });

    test('completes even when Firestore throws (error isolation)', () async {
      when(() => mockRemote.load()).thenAnswer(
        (_) async => KnowledgeGraph.empty,
      );
      await dualRepo.load(); // sets _seeded = true

      when(() => mockRemote.save(any())).thenThrow(
        Exception('Firestore offline'),
      );

      final graph = sampleGraph();
      // Should NOT throw.
      await dualRepo.save(graph);

      // Drift should still have the data.
      final driftGraph = await driftRepo.load();
      expect(driftGraph.concepts.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // updateQuizItem — dual write
  // ---------------------------------------------------------------------------

  group('updateQuizItem', () {
    test('writes to both repos', () async {
      stubRemoteWritesSucceed();
      when(() => mockRemote.load()).thenAnswer(
        (_) async => KnowledgeGraph.empty,
      );
      await dualRepo.load();

      final graph = sampleGraph();
      await dualRepo.save(graph);

      final updatedItem = testQuizItem(
        id: 'q1',
        conceptId: 'c1',
        difficulty: 6.0,
        stability: 20.0,
        fsrsState: 2,
        reviewCount: 5,
      );
      final updatedGraph = graph.withUpdatedQuizItem(updatedItem);

      await dualRepo.updateQuizItem(updatedGraph, updatedItem);

      // Drift should reflect the update.
      final driftGraph = await driftRepo.load();
      final q = driftGraph.quizItems.firstWhere((q) => q.id == 'q1');
      expect(q.difficulty, 6.0);
      expect(q.stability, 20.0);
      expect(q.reviewCount, 5);

      // Remote should have been called.
      verify(
        () => mockRemote.updateQuizItem(updatedGraph, updatedItem),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // saveSplitData — dual write
  // ---------------------------------------------------------------------------

  group('saveSplitData', () {
    test('writes to both repos', () async {
      stubRemoteWritesSucceed();
      when(() => mockRemote.load()).thenAnswer(
        (_) async => KnowledgeGraph.empty,
      );
      await dualRepo.load();

      final graph = sampleGraph();
      await dualRepo.save(graph);

      final newConcepts = [
        Concept(
          id: 'c1-sub1',
          name: 'Docker Images',
          description: 'Immutable snapshots',
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
      ];
      final newQuizItems = [
        testQuizItem(id: 'q-sub1', conceptId: 'c1-sub1'),
      ];

      await dualRepo.saveSplitData(
        graph: graph,
        concepts: newConcepts,
        relationships: newRelationships,
        quizItems: newQuizItems,
      );

      // Drift should have originals + new split data.
      final driftGraph = await driftRepo.load();
      expect(driftGraph.concepts.length, 3);
      expect(driftGraph.relationships.length, 2);
      expect(driftGraph.quizItems.length, 2);

      // Remote should have been called.
      verify(
        () => mockRemote.saveSplitData(
          graph: graph,
          concepts: newConcepts,
          relationships: newRelationships,
          quizItems: newQuizItems,
        ),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // watch — delegates to primary only
  // ---------------------------------------------------------------------------

  group('watch', () {
    test('emits from Drift stream only', () async {
      stubRemoteWritesSucceed();
      when(() => mockRemote.load()).thenAnswer(
        (_) async => KnowledgeGraph.empty,
      );
      await dualRepo.load();

      // Save data through the dual-write repo.
      await dualRepo.save(sampleGraph());

      final emissions = <KnowledgeGraph>[];
      final completer = Completer<void>();
      var count = 0;

      final subscription = dualRepo.watch().listen((graph) {
        emissions.add(graph);
        count++;
        if (count >= 2) completer.complete();
      });

      // Wait for initial emission.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emissions.length, 1);
      expect(emissions.first.concepts.length, 2);

      // Trigger a change through primary.
      await dualRepo.save(KnowledgeGraph(
        concepts: [
          Concept(
            id: 'cx',
            name: 'Rust',
            description: 'Systems language',
            sourceDocumentId: 'docX',
          ),
        ],
      ));

      await completer.future.timeout(const Duration(seconds: 5));

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.concepts.length, 1);
      expect(emissions.last.concepts.first.id, 'cx');

      // Remote.watch() should never have been called.
      verifyNever(() => mockRemote.watch());

      await subscription.cancel();
    });
  });
}
