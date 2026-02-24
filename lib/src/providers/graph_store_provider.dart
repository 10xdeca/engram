import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/drift/drift_graph_repository.dart';
import '../storage/drift/engram_database.dart';
import '../storage/firestore_graph_repository.dart';
import '../storage/graph_repository.dart';
import 'auth_provider.dart';

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
/// Uses [FirestoreGraphRepository] when user is authenticated;
/// falls back to [DriftGraphRepository] (SQLite) for unauthenticated/offline
/// use, replacing the old JSON-file [LocalGraphRepository].
final graphRepositoryProvider = Provider<GraphRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  final firestore = ref.watch(firestoreProvider);

  if (user != null) {
    return FirestoreGraphRepository(firestore: firestore, userId: user.uid);
  }

  final db = ref.watch(engramDatabaseProvider);
  return DriftGraphRepository(db: db);
});

/// Backward-compatible alias so existing code referencing
/// [graphStoreProvider] continues to compile during migration.
@Deprecated('Use graphRepositoryProvider instead')
final graphStoreProvider = graphRepositoryProvider;
