/// Configurable retry policy with exponential back-off, jitter, and
/// user-defined retry-eligibility predicates.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Defines how failed requests should be retried.
///
/// ```dart
/// final policy = RetryPolicy(
///   maxRetries: 3,
///   backoff: ExponentialBackoff(baseDelay: Duration(seconds: 1)),
/// );
/// ```
@immutable
class RetryPolicy {
  /// Creates a [RetryPolicy].
  ///
  /// * [maxRetries] — maximum number of retry attempts (default 3).
  /// * [backoff] — strategy that computes the delay between retries.
  /// * [shouldRetry] — optional predicate; if provided, only errors for which
  ///   this returns `true` are retried. By default everything is retryable.
  const RetryPolicy({
    this.maxRetries = 3,
    this.backoff = const ExponentialBackoff(),
    this.shouldRetry,
  });

  /// Default policy: 3 retries with exponential back-off starting at 1 s.
  static const RetryPolicy defaultPolicy = RetryPolicy();

  /// No-retry policy.
  static const RetryPolicy none = RetryPolicy(maxRetries: 0);

  /// Maximum number of retries.
  final int maxRetries;

  /// Back-off strategy.
  final BackoffStrategy backoff;

  /// Optional predicate. When `null`, every error is retried.
  final bool Function(Object error, int attempt)? shouldRetry;

  /// Whether [attempt] (0-indexed) is within the allowed retry count.
  bool canRetry(int attempt) => attempt < maxRetries;

  /// Returns the delay to wait before the given [attempt] (0-indexed).
  Duration delayFor(int attempt) => backoff.delay(attempt);
}

// ---------------------------------------------------------------------------
// Back-off strategies
// ---------------------------------------------------------------------------

/// Abstract interface for back-off strategies.
@immutable
abstract class BackoffStrategy {
  const BackoffStrategy();

  /// Returns the delay before the given [attempt] (0-indexed).
  Duration delay(int attempt);
}

/// Exponential back-off: `baseDelay * 2^attempt`, optionally jittered.
///
/// ```text
/// attempt 0 → 1 s
/// attempt 1 → 2 s
/// attempt 2 → 4 s
/// ...
/// ```
@immutable
class ExponentialBackoff extends BackoffStrategy {
  const ExponentialBackoff({
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.withJitter = true,
  });

  /// The base delay (multiplied by 2^attempt).
  final Duration baseDelay;

  /// Upper bound — the computed delay is capped at this value.
  final Duration maxDelay;

  /// When `true`, a random jitter of ±25 % is applied to reduce thundering
  /// herd effects.
  final bool withJitter;

  static final math.Random _random = math.Random();

  @override
  Duration delay(int attempt) {
    final ms = baseDelay.inMilliseconds * math.pow(2, attempt);
    var capped = math.min(ms.toInt(), maxDelay.inMilliseconds);

    if (withJitter) {
      // Apply ±25 % jitter.
      final jitter = (capped * 0.25).toInt();
      capped = capped - jitter + _random.nextInt(jitter * 2 + 1);
    }

    return Duration(milliseconds: capped);
  }
}

/// Constant back-off: always waits the same [duration].
@immutable
class ConstantBackoff extends BackoffStrategy {
  const ConstantBackoff({
    this.duration = const Duration(seconds: 2),
  });

  final Duration duration;

  @override
  Duration delay(int attempt) => duration;
}

/// Linear back-off: `baseDelay * (attempt + 1)`.
@immutable
class LinearBackoff extends BackoffStrategy {
  const LinearBackoff({
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  });

  final Duration baseDelay;
  final Duration maxDelay;

  @override
  Duration delay(int attempt) {
    final ms = baseDelay.inMilliseconds * (attempt + 1);
    final capped = math.min(ms, maxDelay.inMilliseconds);
    return Duration(milliseconds: capped);
  }
}
