import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// A repair mission auto-generated after a network fracture (Tier 3).
///
/// Contains the specific concepts that need review to reconnect the fractured
/// islands. Concepts reviewed during an active mission earn 1.5x mastery credit.
@immutable
class RepairMission {
  RepairMission({
    required this.id,
    List<String> conceptIds = const [],
    List<String> reviewedConceptIds = const [],
    required this.createdAt,
    this.completedAt,
    this.catastropheEventId,
  })  : conceptIds = IList(conceptIds),
        reviewedConceptIds = IList(reviewedConceptIds);

  const RepairMission._raw({
    required this.id,
    required this.conceptIds,
    required this.reviewedConceptIds,
    required this.createdAt,
    this.completedAt,
    this.catastropheEventId,
  });

  factory RepairMission.fromJson(Map<String, dynamic> json) {
    return RepairMission._raw(
      id: json['id'] as String,
      conceptIds:
          (json['conceptIds'] as List<dynamic>?)?.cast<String>().lock ??
              const IListConst([]),
      reviewedConceptIds:
          (json['reviewedConceptIds'] as List<dynamic>?)?.cast<String>().lock ??
              const IListConst([]),
      createdAt: json['createdAt'] as String,
      completedAt: json['completedAt'] as String?,
      catastropheEventId: json['catastropheEventId'] as String?,
    );
  }

  final String id;

  /// Concept IDs that need to be reviewed to complete the mission.
  final IList<String> conceptIds;

  /// Concept IDs that have been reviewed so far.
  final IList<String> reviewedConceptIds;

  final String createdAt;
  final String? completedAt;
  final String? catastropheEventId;

  bool get isComplete => completedAt != null;

  /// Progress as a fraction (0.0 – 1.0).
  double get progress {
    if (conceptIds.isEmpty) return 1.0;
    return reviewedConceptIds.length / conceptIds.length;
  }

  /// Number of concepts remaining.
  int get remaining => conceptIds.length - reviewedConceptIds.length;

  RepairMission withReviewedConcept(String conceptId, {required DateTime now}) {
    if (reviewedConceptIds.contains(conceptId)) return this;
    if (!conceptIds.contains(conceptId)) return this;
    final updated = reviewedConceptIds.add(conceptId);
    return RepairMission._raw(
      id: id,
      conceptIds: conceptIds,
      reviewedConceptIds: updated,
      createdAt: createdAt,
      completedAt:
          updated.length >= conceptIds.length
              ? now.toUtc().toIso8601String()
              : null,
      catastropheEventId: catastropheEventId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conceptIds': conceptIds.toList(),
        'reviewedConceptIds': reviewedConceptIds.toList(),
        'createdAt': createdAt,
        'completedAt': completedAt,
        'catastropheEventId': catastropheEventId,
      };
}
