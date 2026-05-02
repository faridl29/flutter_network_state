/// Lightweight Cubit-style base class for network-aware state management.
///
/// This does NOT depend on the `flutter_bloc` package. It provides a minimal
/// Cubit-like API (`emit`, `state`, `stream`) built on plain Dart streams,
/// so developers who prefer the Cubit pattern can use it without pulling in
/// the full Bloc dependency.
///
/// If you already use `flutter_bloc`, see [bloc_extension.dart] instead.
library;

import 'dart:async';

import 'package:flutter_network_state/core/network_state.dart';
import 'package:flutter_network_state/core/network_strategy.dart';
import 'package:flutter_network_state/manager/network_manager.dart';

/// A lightweight Cubit-like base class that manages [NetworkState] and
/// integrates with [NetworkManager].
///
/// Subclass this to create feature-specific cubits:
///
/// ```dart
/// class UserCubit extends NetworkCubit {
///   UserCubit(NetworkManager manager) : super(manager);
///
///   Future<void> loadUser() async {
///     await executeRequest(
///       () => api.getUser(),
///       cacheKey: 'user',
///       strategy: CacheFirst(),
///     );
///   }
/// }
///
/// // Usage
/// final cubit = UserCubit(networkManager);
/// cubit.stream.listen((state) {
///   switch (state) {
///     case Success<User>() => print(state.data.name);
///     case Loading() => print('loading...');
///     // ...
///   }
/// });
/// await cubit.loadUser();
/// ```
abstract class NetworkCubit {
  /// Creates a [NetworkCubit] with the given [NetworkManager].
  NetworkCubit(this._manager) {
    _connectivitySub = _manager.stateStream.listen((state) {
      // Only forward connectivity-level states (Offline, Syncing, Idle).
      // Request-level states are handled by [executeRequest].
      if (state is Offline || state is Syncing) {
        emit(state);
      }
    });
  }

  final NetworkManager _manager;
  final _controller = StreamController<NetworkState>.broadcast();
  StreamSubscription<NetworkState>? _connectivitySub;

  NetworkState _state = const Idle();
  bool _isClosed = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// The current state.
  NetworkState get state => _state;

  /// Stream of state changes.
  Stream<NetworkState> get stream => _controller.stream;

  /// The underlying [NetworkManager].
  NetworkManager get manager => _manager;

  /// Whether the cubit has been closed.
  bool get isClosed => _isClosed;

  /// Emit a new state and notify listeners.
  void emit(NetworkState newState) {
    if (_isClosed) return;
    _state = newState;
    _controller.add(newState);
  }

  /// Execute a request through [NetworkManager] and emit state transitions.
  ///
  /// Emits: `Loading` → `Success<T>` or `Error`/`Offline`.
  Future<T?> executeRequest<T>(
    Future<T> Function() requestFn, {
    String? cacheKey,
    NetworkStrategy? strategy,
    Duration? cacheTtl,
  }) async {
    emit(const Loading());

    try {
      final data = await _manager.request<T>(
        requestFn,
        cacheKey: cacheKey,
        strategy: strategy,
        cacheTtl: cacheTtl,
      );
      emit(Success<T>(data));
      return data;
    } catch (e) {
      if (!_manager.isOnline) {
        emit(Offline(queuedRequests: _manager.queue.length));
      } else {
        emit(Error(e.toString(), exception: e));
      }
      return null;
    }
  }

  /// Close the cubit and release resources.
  Future<void> close() async {
    _isClosed = true;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _controller.close();
  }
}
