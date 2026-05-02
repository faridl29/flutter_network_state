/// Helpers for integrating [NetworkManager] with Riverpod.
///
/// This file does NOT depend on the `riverpod` package. Instead, it provides
/// factory functions and patterns that users can drop into their Riverpod
/// provider definitions.
///
/// ## Usage with Riverpod
///
/// ```dart
/// // 1. Provide the NetworkManager as a singleton
/// final networkManagerProvider = Provider<NetworkManager>((ref) {
///   final manager = NetworkManager();
///   ref.onDispose(() => manager.dispose());
///   return manager;
/// });
///
/// // 2. Use the built-in stream notifier
/// final networkStateProvider = StreamProvider<NetworkState>((ref) {
///   final manager = ref.watch(networkManagerProvider);
///   return manager.stateStream;
/// });
///
/// // 3. Create feature-specific providers using NetworkStateNotifier
/// final userProvider =
///     StateNotifierProvider<NetworkStateNotifier, NetworkState>((ref) {
///   return NetworkStateNotifier(ref.watch(networkManagerProvider));
/// });
///
/// // In your widget:
/// final state = ref.watch(userProvider);
/// switch (state) {
///   case Success<User>() => Text(state.data.name),
///   case Loading() => CircularProgressIndicator(),
///   // ...
/// }
///
/// // Trigger a request:
/// ref.read(userProvider.notifier).execute(
///   () => api.getUser(),
///   cacheKey: 'user',
///   strategy: CacheFirst(),
/// );
/// ```
library;

import 'dart:async';

import 'package:flutter_network_state/core/network_state.dart';
import 'package:flutter_network_state/core/network_strategy.dart';
import 'package:flutter_network_state/manager/network_manager.dart';

/// A Riverpod-compatible `StateNotifier`-style class that manages
/// [NetworkState] and integrates with [NetworkManager].
///
/// This class follows the StateNotifier contract (exposes `state` and
/// a stream) but does NOT import `riverpod` or `state_notifier`. It can
/// be used with:
///
/// - `StateNotifierProvider` (Riverpod)
/// - Any class that expects a `state` getter + stream
///
/// For full Riverpod integration, wrap this in your provider:
///
/// ```dart
/// final myProvider =
///     StateNotifierProvider<NetworkStateNotifier, NetworkState>((ref) {
///   return NetworkStateNotifier(ref.watch(networkManagerProvider));
/// });
/// ```
class NetworkStateNotifier {
  /// Creates a [NetworkStateNotifier] bound to the given [NetworkManager].
  NetworkStateNotifier(this._manager) {
    _connectivitySub = _manager.stateStream.listen((s) {
      if (s is Offline || s is Syncing || s is Idle) {
        state = s;
      }
    });
  }

  final NetworkManager _manager;
  final _controller = StreamController<NetworkState>.broadcast();
  StreamSubscription<NetworkState>? _connectivitySub;

  NetworkState _state = const Idle();

  /// The current state.
  NetworkState get state => _state;

  /// Set a new state and notify listeners.
  set state(NetworkState newState) {
    _state = newState;
    if (!_controller.isClosed) {
      _controller.add(newState);
    }
  }

  /// Stream of state changes — compatible with Riverpod's
  /// `StateNotifier.stream`.
  Stream<NetworkState> get stream => _controller.stream;

  /// The underlying [NetworkManager].
  NetworkManager get manager => _manager;

  /// Execute a network request and update state automatically.
  ///
  /// ```dart
  /// ref.read(userProvider.notifier).execute(
  ///   () => api.getUser(),
  ///   cacheKey: 'user',
  ///   strategy: CacheFirst(),
  /// );
  /// ```
  Future<T?> execute<T>(
    Future<T> Function() requestFn, {
    String? cacheKey,
    NetworkStrategy? strategy,
    Duration? cacheTtl,
  }) async {
    state = const Loading();

    try {
      final data = await _manager.request<T>(
        requestFn,
        cacheKey: cacheKey,
        strategy: strategy,
        cacheTtl: cacheTtl,
      );
      state = Success<T>(data);
      return data;
    } catch (e) {
      if (!_manager.isOnline) {
        state = Offline(queuedRequests: _manager.queue.length);
      } else {
        state = Error(e.toString(), exception: e);
      }
      return null;
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _controller.close();
  }
}

/// Extension on [NetworkManager] for creating Riverpod-friendly providers.
extension NetworkManagerRiverpodExtension on NetworkManager {
  /// Creates a [NetworkStateNotifier] bound to this manager.
  ///
  /// ```dart
  /// final provider = StateNotifierProvider<NetworkStateNotifier, NetworkState>(
  ///   (ref) => ref.watch(networkManagerProvider).createNotifier(),
  /// );
  /// ```
  NetworkStateNotifier createNotifier() => NetworkStateNotifier(this);
}
