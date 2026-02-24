import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

import 'timestamped_concept.dart';

/// Phase of the narration pipeline state machine.
///
/// Flow: idle → generatingScript → synthesizingAudio → ready → playing ↔ paused → completed
/// Any phase may transition to error on failure.
enum NarrationPhase {
  /// No narration active.
  idle,

  /// Claude is generating the concept-annotated script.
  generatingScript,

  /// ElevenLabs is synthesizing audio with character timestamps.
  synthesizingAudio,

  /// Audio is ready to play.
  ready,

  /// Audio is currently playing.
  playing,

  /// Playback is paused.
  paused,

  /// Playback completed naturally.
  completed,

  /// An error occurred at any stage.
  error,
}

/// Immutable state of a narration session.
///
/// Follows the same `copyWith()` pattern used by [RecommendationState].
/// Drives both audio playback and graph glow via [activeConcepts].
@immutable
class NarrationSession {
  const NarrationSession({
    this.phase = NarrationPhase.idle,
    this.scriptText = '',
    this.timestampedConcepts = const IListConst([]),
    this.audioBytes,
    this.durationSeconds = 0.0,
    this.positionSeconds = 0.0,
    this.activeConcepts = const ISetConst({}),
    this.errorMessage = '',
  });

  const NarrationSession._raw({
    required this.phase,
    required this.scriptText,
    required this.timestampedConcepts,
    required this.audioBytes,
    required this.durationSeconds,
    required this.positionSeconds,
    required this.activeConcepts,
    required this.errorMessage,
  });

  /// Current phase of the narration pipeline.
  final NarrationPhase phase;

  /// The stripped (tag-free) narration script text.
  final String scriptText;

  /// Concept → time-range mappings for glow synchronization.
  final IList<TimestampedConcept> timestampedConcepts;

  /// Raw audio bytes from ElevenLabs TTS.
  final Uint8List? audioBytes;

  /// Total audio duration in seconds.
  final double durationSeconds;

  /// Current playback position in seconds.
  final double positionSeconds;

  /// Concept IDs that are currently being narrated.
  final ISet<String> activeConcepts;

  /// Error description when [phase] is [NarrationPhase.error].
  final String errorMessage;

  /// Create a copy with the specified fields replaced.
  NarrationSession copyWith({
    NarrationPhase? phase,
    String? scriptText,
    IList<TimestampedConcept>? timestampedConcepts,
    Uint8List? audioBytes,
    double? durationSeconds,
    double? positionSeconds,
    ISet<String>? activeConcepts,
    String? errorMessage,
  }) {
    return NarrationSession._raw(
      phase: phase ?? this.phase,
      scriptText: scriptText ?? this.scriptText,
      timestampedConcepts: timestampedConcepts ?? this.timestampedConcepts,
      audioBytes: audioBytes ?? this.audioBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      activeConcepts: activeConcepts ?? this.activeConcepts,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
