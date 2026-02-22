import 'package:engram/src/models/knowledge_gap.dart';
import 'package:engram/src/models/knowledge_graph.dart';
import 'package:engram/src/models/network_health.dart';
import 'package:engram/src/models/recommendation.dart';
import 'package:engram/src/models/relationship.dart';
import 'package:engram/src/providers/gap_analysis_provider.dart';
import 'package:engram/src/providers/knowledge_graph_provider.dart';
import 'package:engram/src/providers/network_health_provider.dart';
import 'package:engram/src/providers/recommendation_provider.dart';
import 'package:engram/src/ui/screens/recommendations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreloadedGraphNotifier extends KnowledgeGraphNotifier {
  _PreloadedGraphNotifier(this._graph);

  final KnowledgeGraph _graph;

  @override
  Future<KnowledgeGraph> build() async => _graph;
}

void main() {
  group('RecommendationsScreen', () {
    Widget buildApp({
      List<KnowledgeGap> gaps = const [],
      RecommendationState recState = const RecommendationState(),
    }) {
      return ProviderScope(
        overrides: [
          knowledgeGraphProvider.overrideWith(
            () => _PreloadedGraphNotifier(KnowledgeGraph.empty),
          ),
          networkHealthProvider.overrideWithValue(
            const NetworkHealth(score: 1.0, tier: HealthTier.healthy),
          ),
          gapAnalysisProvider.overrideWithValue(gaps),
          recommendationProvider.overrideWith(
            () => _FixedRecommendationNotifier(recState),
          ),
        ],
        child: const MaterialApp(home: RecommendationsScreen()),
      );
    }

    testWidgets('shows no-gaps message when graph is well-connected',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No knowledge gaps detected'), findsOneWidget);
    });

    testWidgets('shows gap count and gap chips when gaps exist',
        (tester) async {
      final gaps = [
        KnowledgeGap(
          type: GapType.clusterIsolation,
          description: 'ML and DB are disconnected',
          severity: 0.8,
          bridgePotential: 0.9,
        ),
        KnowledgeGap(
          type: GapType.structuralThinness,
          description: 'Concept X has few connections',
          severity: 0.4,
          bridgePotential: 0.3,
        ),
      ];

      await tester.pumpWidget(buildApp(gaps: gaps));
      await tester.pumpAndSettle();

      expect(find.text('2 knowledge gaps detected'), findsOneWidget);
      expect(find.text('ML and DB are disconnected'), findsOneWidget);
    });

    testWidgets('shows scan prompt when gaps exist but idle', (tester) async {
      final gaps = [
        KnowledgeGap(
          type: GapType.clusterIsolation,
          description: 'Gap',
          severity: 0.5,
          bridgePotential: 0.5,
        ),
      ];

      await tester.pumpWidget(buildApp(gaps: gaps));
      await tester.pumpAndSettle();

      expect(find.text('Ready to explore'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
    });

    testWidgets('shows recommendations when phase is done', (tester) async {
      final gaps = [
        KnowledgeGap(
          type: GapType.clusterIsolation,
          description: 'Gap',
          severity: 0.5,
          bridgePotential: 0.5,
        ),
      ];

      final recState = RecommendationState(
        phase: RecommendationPhase.done,
        gaps: gaps,
        recommendations: [
          Recommendation(
            documentId: 'doc-1',
            documentTitle: 'ML for DBAs',
            gap: gaps.first,
            score: 0.85,
            reasoning: 'Bridges ML and databases effectively',
            predictedNewEdges: const [
              PredictedEdge(
                fromConceptName: 'ML',
                toConceptName: 'SQL',
                type: RelationshipType.enables,
                confidence: 0.8,
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(buildApp(gaps: gaps, recState: recState));
      await tester.pumpAndSettle();

      expect(find.text('Recommendations'), findsOneWidget);
      expect(find.text('ML for DBAs'), findsOneWidget);
      expect(find.text('Bridges ML and databases effectively'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
    });

    testWidgets('shows loading when searching', (tester) async {
      final gaps = [
        KnowledgeGap(
          type: GapType.clusterIsolation,
          description: 'Gap',
          severity: 0.5,
          bridgePotential: 0.5,
        ),
      ];

      final recState = RecommendationState(
        phase: RecommendationPhase.searching,
        gaps: gaps,
      );

      await tester.pumpWidget(buildApp(gaps: gaps, recState: recState));
      // Don't pumpAndSettle — loading indicator is animated.
      await tester.pump();

      expect(find.text('Searching Outline wiki...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message on error phase', (tester) async {
      const recState = RecommendationState(
        phase: RecommendationPhase.error,
        errorMessage: 'Network timeout',
      );

      await tester.pumpWidget(buildApp(recState: recState));
      await tester.pumpAndSettle();

      expect(find.text('Error: Network timeout'), findsOneWidget);
    });

    testWidgets('shows empty recommendations message when done with none',
        (tester) async {
      final gaps = [
        KnowledgeGap(
          type: GapType.clusterIsolation,
          description: 'Gap',
          severity: 0.5,
          bridgePotential: 0.5,
        ),
      ];

      final recState = RecommendationState(
        phase: RecommendationPhase.done,
        gaps: gaps,
        recommendations: const [],
      );

      await tester.pumpWidget(buildApp(gaps: gaps, recState: recState));
      await tester.pumpAndSettle();

      expect(find.text('No matching documents found'), findsOneWidget);
    });
  });
}

/// Test notifier that returns a fixed state without side effects.
class _FixedRecommendationNotifier extends RecommendationNotifier {
  _FixedRecommendationNotifier(this._fixedState);

  final RecommendationState _fixedState;

  @override
  RecommendationState build() => _fixedState;

  @override
  Future<void> findRecommendations({int maxGaps = 3}) async {
    // No-op in tests.
  }
}
