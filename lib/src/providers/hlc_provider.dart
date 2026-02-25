import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crdt/hlc_manager.dart';
import '../crdt/node_id_repository.dart';
import 'settings_provider.dart';

/// Provides the [NodeIdRepository] for accessing the device's stable node ID.
///
/// Depends on [sharedPreferencesProvider] which must be overridden in `main()`.
final nodeIdRepositoryProvider = Provider<NodeIdRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return NodeIdRepository(prefs);
});

/// Provides the [HlcManager] for stamping local events and merging remote HLCs.
///
/// This is the entry point for all CRDT timestamp operations. Use it to:
/// - `ref.read(hlcManagerProvider).now()` — stamp a local write
/// - `ref.read(hlcManagerProvider).receive(remote)` — merge an incoming HLC
final hlcManagerProvider = Provider<HlcManager>((ref) {
  final nodeIdRepo = ref.watch(nodeIdRepositoryProvider);
  return HlcManager(nodeId: nodeIdRepo.nodeId);
});
