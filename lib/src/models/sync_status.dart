import 'package:meta/meta.dart';

enum SyncPhase { idle, checking, updatesAvailable, syncing, upToDate, error }

@immutable
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.staleDocumentCount = 0,
    this.staleCollectionIds = const [],
    this.newCollections = const [],
    this.errorMessage = '',
  });

  final SyncPhase phase;
  final int staleDocumentCount;
  final List<String> staleCollectionIds;

  /// Collections found in Outline that haven't been ingested yet.
  /// Each entry is a map with 'id' and 'name' keys.
  final List<Map<String, String>> newCollections;
  final String errorMessage;

  SyncStatus copyWith({
    SyncPhase? phase,
    int? staleDocumentCount,
    List<String>? staleCollectionIds,
    List<Map<String, String>>? newCollections,
    String? errorMessage,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      staleDocumentCount: staleDocumentCount ?? this.staleDocumentCount,
      staleCollectionIds: staleCollectionIds ?? this.staleCollectionIds,
      newCollections: newCollections ?? this.newCollections,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
