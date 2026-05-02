/// Network states that represent the current lifecycle of a network-aware
/// operation. These states are designed to be consumed by any state management
/// solution (Bloc, Riverpod, Provider, etc.) via streams.
///
/// The state hierarchy is intentionally sealed to a known set so that
/// exhaustive pattern matching works cleanly in Dart 3 switch expressions.
library;

import 'package:meta/meta.dart';

/// Base class for all network states.
///
/// Consumers should listen to a `Stream<NetworkState>` and react to each
/// concrete subtype. Example with Dart 3 patterns:
///
/// ```dart
/// switch (state) {
///   case Idle()    => showPlaceholder(),
///   case Loading() => showSpinner(),
///   case Offline() => showOfflineBanner(),
///   case Syncing() => showSyncIndicator(),
///   case Success() => showData(state.data),
///   case Error()   => showError(state.message),
/// }
/// ```
@immutable
sealed class NetworkState {
  const NetworkState();
}

/// Initial idle state — no operation in progress.
final class Idle extends NetworkState {
  const Idle();

  @override
  String toString() => 'NetworkState.Idle';

  @override
  bool operator ==(Object other) => other is Idle;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// An operation is currently in progress.
final class Loading extends NetworkState {
  const Loading({this.message});

  /// Optional human-readable description of what is loading.
  final String? message;

  @override
  String toString() => 'NetworkState.Loading(message: $message)';

  @override
  bool operator ==(Object other) =>
      other is Loading && other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);
}

/// The device is currently offline. No network requests can be fulfilled
/// from the network layer.
final class Offline extends NetworkState {
  const Offline({this.queuedRequests = 0});

  /// Number of requests currently waiting in the offline queue.
  final int queuedRequests;

  @override
  String toString() =>
      'NetworkState.Offline(queuedRequests: $queuedRequests)';

  @override
  bool operator ==(Object other) =>
      other is Offline && other.queuedRequests == queuedRequests;

  @override
  int get hashCode => Object.hash(runtimeType, queuedRequests);
}

/// The sync engine is replaying queued requests after connectivity was
/// restored.
final class Syncing extends NetworkState {
  const Syncing({
    this.totalRequests = 0,
    this.completedRequests = 0,
  });

  /// Total number of queued requests being synced.
  final int totalRequests;

  /// Number of requests that have been successfully replayed so far.
  final int completedRequests;

  /// Progress ratio from 0.0 to 1.0.
  double get progress =>
      totalRequests == 0 ? 0 : completedRequests / totalRequests;

  @override
  String toString() =>
      'NetworkState.Syncing($completedRequests/$totalRequests)';

  @override
  bool operator ==(Object other) =>
      other is Syncing &&
      other.totalRequests == totalRequests &&
      other.completedRequests == completedRequests;

  @override
  int get hashCode =>
      Object.hash(runtimeType, totalRequests, completedRequests);
}

/// An operation completed successfully.
final class Success<T> extends NetworkState {
  const Success(this.data, {this.fromCache = false});

  /// The resulting data.
  final T data;

  /// Whether the data was served from cache rather than the network.
  final bool fromCache;

  @override
  String toString() =>
      'NetworkState.Success(data: $data, fromCache: $fromCache)';

  @override
  bool operator ==(Object other) =>
      other is Success<T> &&
      other.data == data &&
      other.fromCache == fromCache;

  @override
  int get hashCode => Object.hash(runtimeType, data, fromCache);
}

/// An operation failed with an error.
final class Error extends NetworkState {
  const Error(
    this.message, {
    this.exception,
    this.stackTrace,
    this.isRetryable = true,
  });

  /// Human-readable error message.
  final String message;

  /// The original exception, if available.
  final Object? exception;

  /// Stack trace captured at the point of failure.
  final StackTrace? stackTrace;

  /// Whether this error can be retried (e.g. network timeout vs 404).
  final bool isRetryable;

  @override
  String toString() =>
      'NetworkState.Error(message: $message, isRetryable: $isRetryable)';

  @override
  bool operator ==(Object other) =>
      other is Error &&
      other.message == message &&
      other.isRetryable == isRetryable;

  @override
  int get hashCode => Object.hash(runtimeType, message, isRetryable);
}
