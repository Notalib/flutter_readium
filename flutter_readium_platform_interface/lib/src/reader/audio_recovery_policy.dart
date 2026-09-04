import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import '../utils/constants.dart';

/// Configures the automatic audio-stream error recovery loop (retry attempts,
/// backoff, and stall detection) shared by the iOS/Android/web audio
/// navigators.
///
/// Plugin-owned flat config (not a Readium-owned model) — serialized as a
/// flat `Map`, not `json.encode`. Set once via
/// `FlutterReadium().setAudioRecoveryPolicy(...)`; it applies to the next
/// publication opened and to any in-flight recovery loop. There is no
/// mid-stream reconfiguration.
///
/// Defaults reproduce the recovery behaviour that shipped before this policy
/// existed, so an unconfigured consumer sees no change.
@immutable
class AudioRecoveryPolicy with Equatable {
  const AudioRecoveryPolicy({
    this.maxAttempts = 3,
    this.backoffBaseSeconds = 1.0,
    this.stallTimeoutSeconds = 20.0,
    this.connectionTimeoutSeconds = 10.0,
  });

  factory AudioRecoveryPolicy.fromJson(Map<String, dynamic> json) => AudioRecoveryPolicy(
    maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 3,
    backoffBaseSeconds: (json['backoffBaseSeconds'] as num?)?.toDouble() ?? 1.0,
    stallTimeoutSeconds: (json['stallTimeoutSeconds'] as num?)?.toDouble() ?? 20.0,
    connectionTimeoutSeconds: (json['connectionTimeoutSeconds'] as num?)?.toDouble() ?? 10.0,
  );

  /// Maximum number of automatic recovery attempts before entering a
  /// terminal failure state. Defaults to `3`.
  final int maxAttempts;

  /// Base delay, in seconds, for the exponential backoff between recovery
  /// attempts (`backoffBaseSeconds * 2^(attempt-1)`, i.e. 1s/2s/4s with the
  /// default). Defaults to `1.0`.
  final double backoffBaseSeconds;

  /// How long, in seconds, playback can remain in the platform's stalled or
  /// buffering condition before the watchdog synthesizes a retryable error and
  /// enters the recovery loop. Must exceed normal startup and seek buffering.
  /// Defaults to `20.0`.
  final double stallTimeoutSeconds;

  /// How long, in seconds, a single recovery attempt may spend rebuilding the
  /// player / (re)connecting before that attempt is abandoned and the loop
  /// moves on (to the next attempt, or to terminal failure). Bounds a stalled
  /// connect so a dead network can't hang recovery indefinitely. Defaults to
  /// `10.0`.
  final double connectionTimeoutSeconds;

  Map<String, Object?> toJson() => {
    'maxAttempts': maxAttempts,
    'backoffBaseSeconds': backoffBaseSeconds,
    'stallTimeoutSeconds': stallTimeoutSeconds,
    'connectionTimeoutSeconds': connectionTimeoutSeconds,
  };

  AudioRecoveryPolicy copyWith({
    Object? maxAttempts = unset,
    Object? backoffBaseSeconds = unset,
    Object? stallTimeoutSeconds = unset,
    Object? connectionTimeoutSeconds = unset,
  }) => AudioRecoveryPolicy(
    maxAttempts: identical(maxAttempts, unset) ? this.maxAttempts : (maxAttempts as int),
    backoffBaseSeconds: identical(backoffBaseSeconds, unset) ? this.backoffBaseSeconds : (backoffBaseSeconds as double),
    stallTimeoutSeconds: identical(stallTimeoutSeconds, unset)
        ? this.stallTimeoutSeconds
        : (stallTimeoutSeconds as double),
    connectionTimeoutSeconds: identical(connectionTimeoutSeconds, unset)
        ? this.connectionTimeoutSeconds
        : (connectionTimeoutSeconds as double),
  );

  @override
  List<Object?> get props => [
    maxAttempts,
    backoffBaseSeconds,
    stallTimeoutSeconds,
    connectionTimeoutSeconds,
  ];
}
