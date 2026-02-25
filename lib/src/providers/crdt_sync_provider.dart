import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crdt/firestore_sync_transport.dart';
import '../models/crdt_sync_state.dart';
import '../storage/drift/drift_graph_repository.dart';
import 'auth_provider.dart';
import 'clock_provider.dart';
import 'graph_store_provider.dart';
import 'hlc_provider.dart';

/// Peer ID prefix for the Firestore sync_log push bookmark.
const _pushPeerId = 'firestore-sync-log:push';

/// Peer ID prefix for the Firestore sync_log pull bookmark.
const _pullPeerId = 'firestore-sync-log:pull';

// ---------------------------------------------------------------------------
// Typed DriftGraphRepository provider
// ---------------------------------------------------------------------------

/// Provides the [DriftGraphRepository] directly (not the abstract
/// [GraphRepository]) so CRDT sync can call Drift-specific methods like
/// [getChangeset], [mergeChangeset], [getLastSyncedHlc], etc.
final driftGraphRepositoryProvider = Provider<DriftGraphRepository>((ref) {
  final db = ref.watch(engramDatabaseProvider);
  final hlcManager = ref.watch(hlcManagerProvider);
  return DriftGraphRepository(db: db, hlcManager: hlcManager);
});

// ---------------------------------------------------------------------------
// Firestore sync transport provider
// ---------------------------------------------------------------------------

/// Provides the [FirestoreSyncTransport] for the authenticated user.
///
/// Returns `null` when unauthenticated — CRDT sync requires a user ID
/// for the `users/{uid}/sync_log` path.
final firestoreSyncTransportProvider =
    Provider<FirestoreSyncTransport?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;

  final firestore = ref.watch(firestoreProvider);
  return FirestoreSyncTransport(firestore: firestore, userId: user.uid);
});

// ---------------------------------------------------------------------------
// CRDT sync notifier
// ---------------------------------------------------------------------------

final crdtSyncProvider =
    NotifierProvider<CrdtSyncNotifier, CrdtSyncState>(CrdtSyncNotifier.new);

/// Orchestrates CRDT changeset sync between the local Drift database and
/// the Firestore sync_log.
///
/// **Sync lifecycle:**
/// 1. Push: generate local changeset since last push → write to sync_log
/// 2. Pull: read remote changesets since last pull → merge each into Drift
/// 3. Update bookmarks in `drift_sync_metadata`
///
/// Uses separate push/pull HLC bookmarks so a failed pull doesn't block
/// future pushes (and vice versa). Guards against overlapping syncs via
/// [CrdtSyncState.isSyncing].
class CrdtSyncNotifier extends Notifier<CrdtSyncState> {
  Timer? _periodicTimer;

  @override
  CrdtSyncState build() {
    ref.onDispose(_stopTimer);
    return CrdtSyncState.initial;
  }

  /// Runs a full push + pull sync cycle. No-op if already syncing or if
  /// the transport is unavailable (unauthenticated).
  Future<void> sync() async {
    if (state.isSyncing) return;

    final transport = ref.read(firestoreSyncTransportProvider);
    if (transport == null) return;

    final driftRepo = ref.read(driftGraphRepositoryProvider);
    final nodeId = ref.read(nodeIdRepositoryProvider).nodeId;
    final clock = ref.read(clockProvider);

    var pushedCount = 0;
    var pulledCount = 0;
    var mergedCount = 0;

    try {
      // -- Push --
      state = state.copyWith(phase: CrdtSyncPhase.pushing, errorMessage: '');

      final lastPushHlc =
          await driftRepo.getLastSyncedHlc(_pushPeerId) ?? '';
      final changeset =
          await driftRepo.getChangeset(modifiedAfter: lastPushHlc);

      if (!changeset.isEmpty) {
        await transport.pushChangeset(
          changeset: changeset,
          nodeId: nodeId,
        );
        pushedCount = changeset.recordCount;

        // Update push bookmark to the max HLC we just pushed.
        await driftRepo.updateLastSyncedHlc(_pushPeerId, changeset.maxHlc);
      }

      // -- Pull --
      state = state.copyWith(phase: CrdtSyncPhase.pulling);

      final lastPullHlc =
          await driftRepo.getLastSyncedHlc(_pullPeerId) ?? '';
      final pulled = await transport.pullChangesets(
        sinceHlc: lastPullHlc,
        localNodeId: nodeId,
      );
      pulledCount = pulled.length;

      // -- Merge --
      if (pulled.isNotEmpty) {
        state = state.copyWith(phase: CrdtSyncPhase.merging);

        var highestPullHlc = lastPullHlc;
        for (final entry in pulled) {
          mergedCount += await driftRepo.mergeChangeset(entry.changeset);
          if (entry.maxHlc.compareTo(highestPullHlc) > 0) {
            highestPullHlc = entry.maxHlc;
          }
        }

        // Update pull bookmark to the highest maxHlc we merged.
        if (highestPullHlc.isNotEmpty) {
          await driftRepo.updateLastSyncedHlc(_pullPeerId, highestPullHlc);
        }
      }

      state = CrdtSyncState(
        phase: CrdtSyncPhase.idle,
        lastSyncedAt: clock(),
        pushedCount: pushedCount,
        pulledCount: pulledCount,
        mergedCount: mergedCount,
      );
    } catch (e) {
      debugPrint('[CrdtSync] sync failed: $e');
      state = state.copyWith(
        phase: CrdtSyncPhase.error,
        errorMessage: '$e',
      );
    }
  }

  /// Starts periodic sync with the given [interval] (default 5 minutes).
  ///
  /// Triggers an immediate sync, then repeats every [interval]. Calling
  /// this when a timer is already running replaces the existing timer.
  void startPeriodicSync({
    Duration interval = const Duration(minutes: 5),
  }) {
    _stopTimer();
    _periodicTimer = Timer.periodic(interval, (_) => sync());
    // Trigger an immediate sync as well.
    sync();
  }

  /// Stops periodic sync. Safe to call when no timer is active.
  void stopSync() {
    _stopTimer();
  }

  void _stopTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
