import 'package:meta/meta.dart';

import 'concept.dart';
import 'quiz_item.dart';

/// A single sub-concept entry within a split suggestion.
@immutable
class SubConceptEntry {
  const SubConceptEntry({
    required this.concept,
    required this.quizItems,
  });

  final Concept concept;
  final List<QuizItem> quizItems;
}

/// Claude's suggestion for splitting a parent concept into sub-concepts.
@immutable
class SubConceptSuggestion {
  const SubConceptSuggestion({required this.entries});

  final List<SubConceptEntry> entries;
}
