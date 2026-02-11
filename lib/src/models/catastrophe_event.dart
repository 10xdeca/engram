import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

import 'network_health.dart';

/// A recorded catastrophe event in the team's history.
@immutable
class CatastropheEvent {
  CatastropheEvent({
    required this.id,
    required this.tier,
    List<String> affectedConceptIds = const [],
    required this.createdAt,
    this.resolvedAt,
    this.clusterLabel,
  }) : affectedConceptIds = IList(affectedConceptIds);

  const CatastropheEvent._raw({
    required this.id,
    required this.tier,
    required this.affectedConceptIds,
    required this.createdAt,
    this.resolvedAt,
    this.clusterLabel,
  });

  factory CatastropheEvent.fromJson(Map<String, dynamic> json) {
    return CatastropheEvent._raw(
      id: json['id'] as String,
      tier: HealthTier.values.byName(json['tier'] as String),
      affectedConceptIds: (json['affectedConceptIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toIList() ??
          const IListConst([]),
      createdAt: json['createdAt'] as String,
      resolvedAt: json['resolvedAt'] as String?,
      clusterLabel: json['clusterLabel'] as String?,
    );
  }

  final String id;
  final HealthTier tier;
  final IList<String> affectedConceptIds;
  final String createdAt;
  final String? resolvedAt;
  final String? clusterLabel;

  bool get isResolved => resolvedAt != null;

  CatastropheEvent withResolved(String timestamp) => CatastropheEvent._raw(
        id: id,
        tier: tier,
        affectedConceptIds: affectedConceptIds,
        createdAt: createdAt,
        resolvedAt: timestamp,
        clusterLabel: clusterLabel,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tier': tier.name,
        'affectedConceptIds': affectedConceptIds.toList(),
        'createdAt': createdAt,
        'resolvedAt': resolvedAt,
        'clusterLabel': clusterLabel,
      };
}
