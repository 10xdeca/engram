import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/drift/drift_graph_repository.dart';
import '../storage/drift/engram_database.dart';
import '../storage/dual_write_graph_repository.dart';
import '../storage/firestore_graph_repository.dart';
import '../storage/graph_repository.dart';
import 'auth_provider.dart';
import 'hlc_provider.dart';

/// Provides the singleton [EngramDatabase] instance.
///
/// Must be overridden in `main()` with an eagerly-created database:
/// ```dart
/// engramDatabaseProvider.overrideWithValue(EngramDatabase())
/// ```
final engramDatabaseProvider = Provider<EngramDatabase>(
  (_) => throw UnimplementedError('Override in main with actual database'),
);

/// Provides the active [GraphRepository] implementation.
///
/// Authenticated users get a [DualWriteGraphRepository] that reads from
/// [DriftGraphRepository] (local SQLite) and writes to both Drift and
/// [FirestoreGraphRepository]. On first load, existing Firestore data is
/// seeded into Drift for the one-time local-first migration.
///
/// Unauthenticated users get [DriftGraphRepository] only.
final graphRepositoryProvider = Provider<GraphRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  final db = ref.watch(engramDatabaseProvider);
  final hlcManager = ref.watch(hlcManagerProvider);
  final driftRepo = DriftGraphRepository(db: db, hlcManager: hlcManager);

  if (user != null) {
    final firestore = ref.watch(firestoreProvider);
    final firestoreRepo = FirestoreGraphRepository(
      firestore: firestore,
      userId: user.uid,
    );
    return DualWriteGraphRepository(primary: driftRepo, remote: firestoreRepo);
  }

  return driftRepo;
});
