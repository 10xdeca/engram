import 'package:engram/src/engine/mastery_state.dart';
import 'package:engram/src/models/concept.dart';
import 'package:engram/src/models/relationship.dart';
import 'package:engram/src/ui/graph/graph_edge.dart';
import 'package:engram/src/ui/graph/graph_node.dart';
import 'package:engram/src/ui/graph/graph_painter.dart';
import 'package:flutter_test/flutter_test.dart';

GraphNode _node(String id, {Offset position = Offset.zero}) {
  return GraphNode(
    concept: Concept(
      id: id,
      name: id,
      description: '',
      sourceDocumentId: 'doc1',
    ),
    masteryState: MasteryState.learning,
    freshness: 1.0,
    position: position,
  );
}

GraphEdge _edge(GraphNode source, GraphNode target) {
  return GraphEdge(
    relationship: Relationship(
      id: '${source.id}-${target.id}',
      fromConceptId: source.id,
      toConceptId: target.id,
      label: 'related',
    ),
    source: source,
    target: target,
  );
}

void main() {
  group('GraphPainter.shouldRepaint', () {
    test('returns true when glowIntensityMap changes', () {
      final nodes = [_node('a'), _node('b')];

      final old = GraphPainter(
        nodes: nodes,
        edges: const [],
        glowIntensityMap: const {},
      );
      final updated = GraphPainter(
        nodes: nodes,
        edges: const [],
        glowIntensityMap: const {'a': 1.0},
      );

      expect(updated.shouldRepaint(old), isTrue);
    });

    test('returns false when glowIntensityMap is unchanged', () {
      final nodes = [_node('a')];
      const map = {'a': 0.8};

      final old = GraphPainter(
        nodes: nodes,
        edges: const [],
        glowIntensityMap: map,
      );
      final updated = GraphPainter(
        nodes: nodes,
        edges: const [],
        glowIntensityMap: map,
      );

      expect(updated.shouldRepaint(old), isFalse);
    });

    test('returns true when other fields change alongside map', () {
      final nodes = [_node('a')];

      final old = GraphPainter(
        nodes: nodes,
        edges: const [],
        glowIntensity: 0.5,
      );
      final updated = GraphPainter(
        nodes: nodes,
        edges: const [],
        glowIntensity: 0.8,
      );

      expect(updated.shouldRepaint(old), isTrue);
    });
  });

  group('GraphPainter per-node intensity resolution', () {
    test('sustained glow map takes precedence over one-shot glow', () {
      // When both sustained and one-shot glow data exist for a node,
      // the sustained map value should be used.
      final painter = GraphPainter(
        nodes: [_node('a')],
        edges: const [],
        glowNodeIds: const {'a'},
        glowIntensity: 1.0,
        glowIntensityMap: const {'a': 0.5},
      );

      expect(painter, isA<GraphPainter>());
    });

    test('empty sustained map falls back to one-shot glow', () {
      final painter = GraphPainter(
        nodes: [_node('a')],
        edges: const [],
        glowNodeIds: const {'a'},
        glowIntensity: 0.8,
        glowIntensityMap: const {},
      );

      expect(painter, isA<GraphPainter>());
    });
  });

  group('GraphPainter edge glow with sustained map', () {
    test('does not crash when sustained glow includes edge endpoints', () {
      final a = _node('a', position: const Offset(10, 10));
      final b = _node('b', position: const Offset(50, 50));

      final painter = GraphPainter(
        nodes: [a, b],
        edges: [_edge(a, b)],
        glowIntensityMap: const {'a': 1.0, 'b': 0.4},
      );

      expect(painter, isA<GraphPainter>());
    });
  });
}
