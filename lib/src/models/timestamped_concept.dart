import 'package:meta/meta.dart';

/// A concept aligned to a time range in the narration audio.
///
/// Produced by [mapMarkersToTimestamps] after combining character-offset
/// markers with ElevenLabs character-level timing data. Consumed by the
/// narration provider to determine which concepts are active at any playback
/// position.
@immutable
class TimestampedConcept {
  const TimestampedConcept({
    required this.conceptId,
    required this.startTime,
    required this.endTime,
  });

  /// The concept this timestamp refers to.
  final String conceptId;

  /// Start time in seconds within the audio.
  final double startTime;

  /// End time in seconds within the audio.
  final double endTime;

  /// Whether the given playback [position] (in seconds) falls within this
  /// concept's active time range (inclusive on both ends).
  bool containsPosition(double position) =>
      position >= startTime && position <= endTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimestampedConcept &&
          other.conceptId == conceptId &&
          other.startTime == startTime &&
          other.endTime == endTime;

  @override
  int get hashCode => Object.hash(conceptId, startTime, endTime);

  @override
  String toString() =>
      'TimestampedConcept($conceptId, ${startTime.toStringAsFixed(2)}s–'
      '${endTime.toStringAsFixed(2)}s)';
}
