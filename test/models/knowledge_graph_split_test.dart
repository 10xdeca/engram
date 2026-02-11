import 'package:engram/src/models/concept.dart';
import 'package:engram/src/models/knowledge_graph.dart';
import 'package:engram/src/models/quiz_item.dart';
import 'package:engram/src/models/relationship.dart';
import 'package:test/test.dart';

void main() {
  group('withConceptSplit', () {
    test('adds children, relationships, and quiz items', () {
      final graph = KnowledgeGraph(
        concepts: [
          Concept(
            id: 'parent',
            name: 'Parent',
            description: 'The parent concept',
            sourceDocumentId: 'doc1',
          ),
        ],
      );

      final result = graph.withConceptSplit(
        children: [
          Concept(
            id: 'child1',
            name: 'Child 1',
            description: 'First child',
            sourceDocumentId: 'doc1',
            parentConceptId: 'parent',
          ),
          Concept(
            id: 'child2',
            name: 'Child 2',
            description: 'Second child',
            sourceDocumentId: 'doc1',
            parentConceptId: 'parent',
          ),
        ],
        childRelationships: [
          const Relationship(
            id: 'child1-part-of-parent',
            fromConceptId: 'child1',
            toConceptId: 'parent',
            label: 'is part of',
          ),
          const Relationship(
            id: 'child2-part-of-parent',
            fromConceptId: 'child2',
            toConceptId: 'parent',
            label: 'is part of',
          ),
        ],
        childQuizItems: [
          QuizItem.newCard(
            id: 'q-child1',
            conceptId: 'child1',
            question: 'Q1?',
            answer: 'A1.',
          ),
          QuizItem.newCard(
            id: 'q-child2',
            conceptId: 'child2',
            question: 'Q2?',
            answer: 'A2.',
          ),
        ],
      );

      expect(result.concepts.length, 3); // parent + 2 children
      expect(result.relationships.length, 2);
      expect(result.quizItems.length, 2);

      // Original parent still present
      expect(result.concepts.any((c) => c.id == 'parent'), isTrue);

      // Children have parentConceptId set
      final child1 = result.concepts.firstWhere((c) => c.id == 'child1');
      expect(child1.parentConceptId, 'parent');
      expect(child1.isSubConcept, isTrue);
    });

    test('preserves existing graph data', () {
      final graph = KnowledgeGraph(
        concepts: [
          Concept(
            id: 'existing',
            name: 'Existing',
            description: 'desc',
            sourceDocumentId: 'doc1',
          ),
        ],
        quizItems: [
          QuizItem.newCard(
            id: 'q-existing',
            conceptId: 'existing',
            question: 'Q?',
            answer: 'A.',
          ),
        ],
      );

      final result = graph.withConceptSplit(
        children: [
          Concept(
            id: 'new-child',
            name: 'New',
            description: 'desc',
            sourceDocumentId: 'doc1',
            parentConceptId: 'existing',
          ),
        ],
        childRelationships: [],
        childQuizItems: [],
      );

      // Original data preserved
      expect(result.concepts.any((c) => c.id == 'existing'), isTrue);
      expect(result.quizItems.any((q) => q.id == 'q-existing'), isTrue);

      // New child added
      expect(result.concepts.any((c) => c.id == 'new-child'), isTrue);
    });
  });

  group('Concept.parentConceptId', () {
    test('round-trips through JSON', () {
      final concept = Concept(
        id: 'child',
        name: 'Child',
        description: 'desc',
        sourceDocumentId: 'doc1',
        parentConceptId: 'parent',
      );

      final json = concept.toJson();
      expect(json['parentConceptId'], 'parent');

      final restored = Concept.fromJson(json);
      expect(restored.parentConceptId, 'parent');
      expect(restored.isSubConcept, isTrue);
    });

    test('null parentConceptId omitted from JSON', () {
      final concept = Concept(
        id: 'root',
        name: 'Root',
        description: 'desc',
        sourceDocumentId: 'doc1',
      );

      final json = concept.toJson();
      expect(json.containsKey('parentConceptId'), isFalse);

      final restored = Concept.fromJson(json);
      expect(restored.parentConceptId, isNull);
      expect(restored.isSubConcept, isFalse);
    });
  });
}
