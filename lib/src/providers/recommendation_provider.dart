import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../models/knowledge_gap.dart';
import '../models/recommendation.dart';
import 'gap_analysis_provider.dart';
import 'knowledge_graph_provider.dart';
import 'service_providers.dart';

/// Phase of the recommendation pipeline.
enum RecommendationPhase {
  idle,
  analyzing,
  searching,
  evaluating,
  done,
  error,
}

/// State for the recommendation pipeline.
@immutable
class RecommendationState {
  const RecommendationState({
    this.phase = RecommendationPhase.idle,
    this.gaps = const [],
    this.recommendations = const [],
    this.errorMessage = '',
  });

  final RecommendationPhase phase;

  /// Gaps being analyzed (top N by severity).
  final List<KnowledgeGap> gaps;

  /// Final recommendations, sorted by score descending.
  final List<Recommendation> recommendations;

  /// Error message when phase is [RecommendationPhase.error].
  final String errorMessage;

  RecommendationState copyWith({
    RecommendationPhase? phase,
    List<KnowledgeGap>? gaps,
    List<Recommendation>? recommendations,
    String? errorMessage,
  }) {
    return RecommendationState(
      phase: phase ?? this.phase,
      gaps: gaps ?? this.gaps,
      recommendations: recommendations ?? this.recommendations,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final recommendationProvider =
    NotifierProvider<RecommendationNotifier, RecommendationState>(
      RecommendationNotifier.new,
    );

/// Notifier that drives the recommendation pipeline:
/// idle → analyzing → searching → evaluating → done/error.
class RecommendationNotifier extends Notifier<RecommendationState> {
  @override
  RecommendationState build() => const RecommendationState();

  /// Run the full recommendation pipeline for the top [maxGaps] knowledge gaps.
  Future<void> findRecommendations({int maxGaps = 3}) async {
    try {
      // 1. Analyze — read gaps from the gap analysis provider.
      state = state.copyWith(phase: RecommendationPhase.analyzing);
      final allGaps = ref.read(gapAnalysisProvider);
      final topGaps = allGaps.take(maxGaps).toList();

      if (topGaps.isEmpty) {
        state = state.copyWith(
          phase: RecommendationPhase.done,
          gaps: topGaps,
          recommendations: [],
        );
        return;
      }

      state = state.copyWith(gaps: topGaps);

      // 2. Search + evaluate — call RecommendationService for each gap.
      state = state.copyWith(phase: RecommendationPhase.searching);

      final service = ref.read(recommendationServiceProvider);
      final graph = ref.read(knowledgeGraphProvider).valueOrNull;

      final existingConceptNames =
          graph?.concepts.map((c) => c.name).toList() ?? [];
      final ingestedDocIds =
          graph?.documentMetadata.map((d) => d.documentId).toSet() ?? {};

      state = state.copyWith(phase: RecommendationPhase.evaluating);

      final allRecommendations = <Recommendation>[];
      final seenDocIds = <String>{};

      for (final gap in topGaps) {
        final recs = await service.recommend(
          gap: gap,
          existingConceptNames: existingConceptNames,
          ingestedDocumentIds: ingestedDocIds,
        );

        // Deduplicate across gaps (same doc might fill multiple).
        for (final rec in recs) {
          if (seenDocIds.add(rec.documentId)) {
            allRecommendations.add(rec);
          }
        }
      }

      // Sort by score descending.
      allRecommendations.sort((a, b) => b.score.compareTo(a.score));

      state = state.copyWith(
        phase: RecommendationPhase.done,
        recommendations: allRecommendations,
      );
    } catch (e) {
      state = state.copyWith(
        phase: RecommendationPhase.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Reset to idle state.
  void reset() {
    state = const RecommendationState();
  }
}
