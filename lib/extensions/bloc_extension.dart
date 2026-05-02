/// Convenience extensions for integrating [NetworkManager] with the Bloc
/// pattern (or any `StreamController`-based state management).
///
/// These extensions don't depend on `flutter_bloc` directly — they work with
/// plain streams, making them compatible with Cubit, Bloc, Riverpod, or
/// any reactive architecture.
library;

import 'dart:async';

import 'package:flutter_network_state/core/network_state.dart';
import 'package:flutter_network_state/core/network_strategy.dart';
import 'package:flutter_network_state/manager/network_manager.dart';

/// Extension on [NetworkManager] for Bloc-friendly helpers.
extension NetworkManagerBlocExtension on NetworkManager {
  /// Execute a request and pipe [NetworkState] changes into [emit].
  ///
  /// This is designed to be called from a Bloc event handler or Cubit method:
  ///
  /// ```dart
  /// class UserCubit extends Cubit<NetworkState> {
  ///   UserCubit(this._manager) : super(const Idle());
  ///
  ///   final NetworkManager _manager;
  ///
  ///   Future<void> loadUser() async {
  ///     await _manager.executeAndEmit(
  ///       () => api.getUser(),
  ///       emit: emit,
  ///       cacheKey: 'user',
  ///       strategy: CacheFirst(),
  ///     );
  ///   }
  /// }
  /// ```
  Future<T?> executeAndEmit<T>(
    Future<T> Function() requestFn, {
    required void Function(NetworkState) emit,
    String? cacheKey,
    NetworkStrategy? strategy,
    Duration? cacheTtl,
  }) async {
    emit(const Loading());

    try {
      final data = await request<T>(
        requestFn,
        cacheKey: cacheKey,
        strategy: strategy,
        cacheTtl: cacheTtl,
      );
      emit(Success<T>(data));
      return data;
    } catch (e) {
      if (!isOnline) {
        emit(Offline(queuedRequests: queue.length));
      } else {
        emit(Error(e.toString(), exception: e));
      }
      return null;
    }
  }

  /// Creates a [StreamSubscription] that maps [NetworkState] events
  /// into Bloc-compatible `emit` calls.
  ///
  /// Returns the subscription so the Bloc can cancel it on close.
  ///
  /// ```dart
  /// late StreamSubscription _sub;
  ///
  /// @override
  /// Future<void> close() {
  ///   _sub.cancel();
  ///   return super.close();
  /// }
  ///
  /// void _init() {
  ///   _sub = _manager.bindToEmit(emit);
  /// }
  /// ```
  StreamSubscription<NetworkState> bindToEmit(
    void Function(NetworkState) emit,
  ) {
    return stateStream.listen(emit);
  }
}

/// Extension that adds network-awareness to a generic `Stream<T>`.
extension NetworkAwareStream<T> on Stream<T> {
  /// Wraps each emission with [Loading] → [Success] states.
  ///
  /// Errors are emitted as [Error] states.
  Stream<NetworkState> asNetworkStates() {
    return transform(
      StreamTransformer<T, NetworkState>.fromHandlers(
        handleData: (data, sink) {
          sink.add(Success<T>(data));
        },
        handleError: (error, stackTrace, sink) {
          sink.add(Error(
            error.toString(),
            exception: error,
            stackTrace: stackTrace,
          ));
        },
        handleDone: (sink) => sink.close(),
      ),
    );
  }
}
