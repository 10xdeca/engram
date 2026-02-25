import 'package:meta/meta.dart';

/// Phase of the CRDT sync lifecycle.
enum CrdtSyncPhase { idle, pushing, pulling, merging, error }

/// Immutable state for the CRDT changeset sync process.
///
/// Tracks the current phase, last successful sync time, and aggregate
/// counts for push/pull/merge operations (useful for diagnostics and
/// dashboard display).
@immutable
class CrdtSyncState {
  const CrdtSyncState({
    this.phase = CrdtSyncPhase.idle,
    this.lastSyncedAt,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.mergedCount = 0,
    this.errorMessage = '',
  });

  static const initial = CrdtSyncState();

  final CrdtSyncPhase phase;

  /// When the last successful sync completed (null if never synced).
  final DateTime? lastSyncedAt;

  /// Number of rows pushed in the last sync cycle.
  final int pushedCount;

  /// Number of changesets pulled in the last sync cycle.
  final int pulledCount;

  /// Number of rows actually merged (won LWW) in the last sync cycle.
  final int mergedCount;

  /// Error message from the last failed sync, or empty string.
  final String errorMessage;

  /// Whether a sync is currently in progress.
  bool get isSyncing =>
      phase == CrdtSyncPhase.pushing ||
      phase == CrdtSyncPhase.pulling ||
      phase == CrdtSyncPhase.merging;

  CrdtSyncState copyWith({
    CrdtSyncPhase? phase,
    DateTime? lastSyncedAt,
    int? pushedCount,
    int? pulledCount,
    int? mergedCount,
    String? errorMessage,
  }) {
    return CrdtSyncState(
      phase: phase ?? this.phase,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pushedCount: pushedCount ?? this.pushedCount,
      pulledCount: pulledCount ?? this.pulledCount,
      mergedCount: mergedCount ?? this.mergedCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
