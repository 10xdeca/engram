import '../../../models/concept.dart';
import '../../../models/quiz_item.dart';
import '../../../models/relationship.dart';

/// Shared graph test data for the visual lab.
///
/// Extracted from `GraphLabScreen` so that the graph lab, overlay lab, and glow
/// lab tabs can all reuse the same concept topology without duplication.

/// Reference timestamp for quiz item scheduling fields.
final labNow = DateTime.now().toUtc();

// ---------------------------------------------------------------------------
// Initial graph: 6 concepts, 5 relationships, 6 quiz items.
//
// Topology:
//   A (mastered)  <-depends on-  B (learning)
//   A  --relates to-->  C (due)
//   C  <-depends on-  D (locked -- C is unreviewed so D can't unlock)
//   A  <-relates to-  E (fading)
//   E  <-relates to-  F (mastered)
//
// Start with 3 (A, B, C), add D/E/F one at a time via "Add Node".
// ---------------------------------------------------------------------------

final labInitialConcepts = [
  Concept(
    id: 'a',
    name: 'Spaced Repetition',
    description:
        'Reviewing material at increasing intervals to combat forgetting',
    sourceDocumentId: 'doc-lab',
  ),
  Concept(
    id: 'b',
    name: 'Leitner System',
    description: 'Card-box system that sorts flashcards by mastery level',
    sourceDocumentId: 'doc-lab',
  ),
  Concept(
    id: 'c',
    name: 'Active Recall',
    description:
        'Actively retrieving information from memory rather than re-reading',
    sourceDocumentId: 'doc-lab',
  ),
  Concept(
    id: 'd',
    name: 'FSRS Algorithm',
    description: 'Free Spaced Repetition Scheduler — modern successor to SM-2',
    sourceDocumentId: 'doc-lab',
  ),
  Concept(
    id: 'e',
    name: 'Forgetting Curve',
    description: 'Ebbinghaus curve showing exponential memory decay over time',
    sourceDocumentId: 'doc-lab',
  ),
  Concept(
    id: 'f',
    name: 'Memory Palace',
    description: 'Method of loci — placing items in imagined spatial locations',
    sourceDocumentId: 'doc-lab',
  ),
];

final labInitialRelationships = [
  const Relationship(
    id: 'r1',
    fromConceptId: 'b',
    toConceptId: 'a',
    label: 'depends on',
  ),
  const Relationship(
    id: 'r2',
    fromConceptId: 'd',
    toConceptId: 'c',
    label: 'depends on',
  ),
  const Relationship(
    id: 'r3',
    fromConceptId: 'c',
    toConceptId: 'a',
    label: 'relates to',
  ),
  const Relationship(
    id: 'r4',
    fromConceptId: 'e',
    toConceptId: 'a',
    label: 'relates to',
  ),
  const Relationship(
    id: 'r5',
    fromConceptId: 'f',
    toConceptId: 'e',
    label: 'relates to',
  ),
];

final labInitialQuizItems = [
  // A -> mastered: FSRS review state, high stability, recent review
  QuizItem(
    id: 'q1',
    conceptId: 'a',
    question: 'What is spaced repetition?',
    answer: 'Reviewing at increasing intervals to combat forgetting',
    interval: 30,
    nextReview: labNow.add(const Duration(days: 30)),
    lastReview: labNow.subtract(const Duration(days: 2)),
    difficulty: 5.0,
    stability: 100.0,
    fsrsState: 2,
    lapses: 0,
  ),
  // B -> learning: FSRS learning state, low stability
  QuizItem(
    id: 'q2',
    conceptId: 'b',
    question: 'What is the Leitner system?',
    answer: 'A card-box sorting system for spaced review',
    interval: 7,
    nextReview: labNow.add(const Duration(days: 7)),
    lastReview: labNow.subtract(const Duration(days: 1)),
    difficulty: 5.0,
    stability: 5.0,
    fsrsState: 1,
    lapses: 0,
  ),
  // C -> due: never reviewed
  QuizItem(
    id: 'q3',
    conceptId: 'c',
    question: 'What is active recall?',
    answer: 'Actively retrieving information from memory',
    interval: 0,
    nextReview: labNow,
    lastReview: null,
  ),
  // D -> locked: C is its prerequisite and C is not graduated
  QuizItem(
    id: 'q4',
    conceptId: 'd',
    question: 'What is FSRS?',
    answer: 'Free Spaced Repetition Scheduler',
    interval: 0,
    nextReview: labNow,
    lastReview: null,
  ),
  // E -> fading: FSRS review state but lastReview > 30 days ago
  QuizItem(
    id: 'q5',
    conceptId: 'e',
    question: 'What is the forgetting curve?',
    answer: 'Exponential memory decay over time (Ebbinghaus)',
    interval: 30,
    nextReview: labNow,
    lastReview: labNow.subtract(const Duration(days: 45)),
    difficulty: 5.0,
    stability: 1000.0,
    fsrsState: 2,
    lapses: 0,
  ),
  // F -> mastered: FSRS review state, high stability, recent review
  QuizItem(
    id: 'q6',
    conceptId: 'f',
    question: 'What is a memory palace?',
    answer: 'Method of loci — spatial memory technique',
    interval: 25,
    nextReview: labNow.add(const Duration(days: 25)),
    lastReview: labNow.subtract(const Duration(days: 3)),
    difficulty: 5.0,
    stability: 80.0,
    fsrsState: 2,
    lapses: 0,
  ),
];

// ---------------------------------------------------------------------------
// Batch 2: simulated second document ingestion — "Learning Techniques".
//
// 5 new concepts that connect to existing nodes A and C.
// Topology:
//   G (learning)  ──relates to──>  A
//   H (due)       ──relates to──>  C
//   I (locked)    ──depends on──>  C  (C is due, so I is locked)
//   J (locked)    ──depends on──>  H  (H is due, so J is locked)
//   K (due)       ──relates to──>  G
// ---------------------------------------------------------------------------

final labBatch2Concepts = [
  Concept(
    id: 'g',
    name: 'Interleaving',
    description: 'Mixing different topics during study sessions',
    sourceDocumentId: 'doc-lab-2',
  ),
  Concept(
    id: 'h',
    name: 'Desirable Difficulty',
    description: 'Making learning harder to improve long-term retention',
    sourceDocumentId: 'doc-lab-2',
  ),
  Concept(
    id: 'i',
    name: 'Testing Effect',
    description: 'Taking tests improves long-term retention more than re-study',
    sourceDocumentId: 'doc-lab-2',
  ),
  Concept(
    id: 'j',
    name: 'Elaborative Interrogation',
    description: 'Asking "why" and "how" questions to deepen understanding',
    sourceDocumentId: 'doc-lab-2',
  ),
  Concept(
    id: 'k',
    name: 'Dual Coding',
    description:
        'Combining verbal and visual information for stronger encoding',
    sourceDocumentId: 'doc-lab-2',
  ),
];

final labBatch2Relationships = [
  const Relationship(
    id: 'r6',
    fromConceptId: 'g',
    toConceptId: 'a',
    label: 'relates to',
  ),
  const Relationship(
    id: 'r7',
    fromConceptId: 'h',
    toConceptId: 'c',
    label: 'relates to',
  ),
  const Relationship(
    id: 'r8',
    fromConceptId: 'i',
    toConceptId: 'c',
    label: 'depends on',
  ),
  const Relationship(
    id: 'r9',
    fromConceptId: 'j',
    toConceptId: 'h',
    label: 'depends on',
  ),
  const Relationship(
    id: 'r10',
    fromConceptId: 'k',
    toConceptId: 'g',
    label: 'relates to',
  ),
];

final labBatch2QuizItems = [
  // G -> learning: FSRS learning state
  QuizItem(
    id: 'q7',
    conceptId: 'g',
    question: 'What is interleaving?',
    answer: 'Mixing different topics during study sessions',
    interval: 7,
    nextReview: labNow.add(const Duration(days: 7)),
    lastReview: labNow.subtract(const Duration(days: 1)),
    difficulty: 5.0,
    stability: 5.0,
    fsrsState: 1,
    lapses: 0,
  ),
  // H -> due: never reviewed
  QuizItem(
    id: 'q8',
    conceptId: 'h',
    question: 'What is desirable difficulty?',
    answer: 'Making learning harder to improve retention',
    interval: 0,
    nextReview: labNow,
    lastReview: null,
  ),
  // I -> locked (depends on C which is due)
  QuizItem(
    id: 'q9',
    conceptId: 'i',
    question: 'What is the testing effect?',
    answer: 'Taking tests improves long-term retention',
    interval: 0,
    nextReview: labNow,
    lastReview: null,
  ),
  // J -> locked (depends on H which is due)
  QuizItem(
    id: 'q10',
    conceptId: 'j',
    question: 'What is elaborative interrogation?',
    answer: 'Asking why and how to deepen understanding',
    interval: 0,
    nextReview: labNow,
    lastReview: null,
  ),
  // K -> due: never reviewed
  QuizItem(
    id: 'q11',
    conceptId: 'k',
    question: 'What is dual coding?',
    answer: 'Combining verbal and visual information',
    interval: 0,
    nextReview: labNow,
    lastReview: null,
  ),
];
