import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Node IDs that should glow in the knowledge graph.
///
/// Set by the recommendations screen after a successful ingest,
/// cleared by the graph widget's `onGlowComplete` callback after
/// the glow animation fades out.
final glowNodeIdsProvider = StateProvider<Set<String>>((ref) => const {});
