import 'package:engram/src/engine/highlight_propagation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('propagateHighlight', () {
    // Test graph topology:
    //
    //   A --- B --- C --- D
    //         |
    //         E
    //
    final adjacencyMap = <String, Set<String>>{
      'A': {'B'},
      'B': {'A', 'C', 'E'},
      'C': {'B', 'D'},
      'D': {'C'},
      'E': {'B'},
    };

    test('primary active concept has intensity 1.0', () {
      final result = propagateHighlight(
        activeConcepts: {'B'},
        adjacencyMap: adjacencyMap,
      );

      expect(result['B'], 1.0);
    });

    test('depth-1 neighbors have intensity 0.4', () {
      final result = propagateHighlight(
        activeConcepts: {'B'},
        adjacencyMap: adjacencyMap,
      );

      expect(result['A'], 0.4);
      expect(result['C'], 0.4);
      expect(result['E'], 0.4);
    });

    test('depth-2 neighbors have intensity 0.15', () {
      final result = propagateHighlight(
        activeConcepts: {'B'},
        adjacencyMap: adjacencyMap,
      );

      // D is 2 hops from B (B→C→D)
      expect(result['D'], 0.15);
    });

    test('nodes beyond depth 2 are not included', () {
      // Linear: X --- Y --- Z --- W
      final linearGraph = <String, Set<String>>{
        'X': {'Y'},
        'Y': {'X', 'Z'},
        'Z': {'Y', 'W'},
        'W': {'Z'},
      };

      final result = propagateHighlight(
        activeConcepts: {'X'},
        adjacencyMap: linearGraph,
      );

      expect(result.containsKey('X'), isTrue); // depth 0
      expect(result.containsKey('Y'), isTrue); // depth 1
      expect(result.containsKey('Z'), isTrue); // depth 2
      expect(result.containsKey('W'), isFalse); // depth 3 — excluded
    });

    test('multiple active concepts merge with max intensity', () {
      // Activate both A and D.
      // A=1.0; B is depth-1 from A (0.4) and depth-2 from D (0.15) → max 0.4
      // C is depth-2 from A (0.15) and depth-1 from D (0.4) → max 0.4
      // D=1.0
      final result = propagateHighlight(
        activeConcepts: {'A', 'D'},
        adjacencyMap: adjacencyMap,
      );

      expect(result['A'], 1.0);
      expect(result['D'], 1.0);
      expect(result['B'], 0.4); // max(0.4 from A, 0.15 from D)
      expect(result['C'], 0.4); // max(0.15 from A, 0.4 from D)
    });

    test('disconnected nodes are not affected', () {
      // F is isolated — not in adjacency map of A–E.
      final withIsolated = Map<String, Set<String>>.from(adjacencyMap);
      withIsolated['F'] = {};

      final result = propagateHighlight(
        activeConcepts: {'A'},
        adjacencyMap: withIsolated,
      );

      expect(result.containsKey('F'), isFalse);
    });

    test('returns empty map for no active concepts', () {
      final result = propagateHighlight(
        activeConcepts: {},
        adjacencyMap: adjacencyMap,
      );

      expect(result, isEmpty);
    });

    test('returns empty map for empty adjacency graph', () {
      final result = propagateHighlight(
        activeConcepts: {'A'},
        adjacencyMap: const {},
      );

      // A is active but has no adjacency entry → still gets intensity 1.0.
      expect(result['A'], 1.0);
      expect(result.length, 1);
    });

    test('handles self-referencing adjacency gracefully', () {
      final selfRef = <String, Set<String>>{
        'A': {'A', 'B'},
        'B': {'A'},
      };

      final result = propagateHighlight(
        activeConcepts: {'A'},
        adjacencyMap: selfRef,
      );

      expect(result['A'], 1.0); // primary, not demoted by self-edge
      expect(result['B'], 0.4);
    });

    test('active concept not in adjacency map still has intensity 1.0', () {
      final result = propagateHighlight(
        activeConcepts: {'unknown'},
        adjacencyMap: adjacencyMap,
      );

      expect(result['unknown'], 1.0);
      expect(result.length, 1);
    });
  });
}
