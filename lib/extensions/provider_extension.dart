/// Extensions for integrating [NetworkManager] with [ChangeNotifier]-based
/// state management (Provider, GetIt + ChangeNotifier, etc.).
///
/// This does NOT depend on the `provider` package — it works with the
/// Flutter SDK's built-in [ChangeNotifier].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_network_state/core/network_state.dart';
import 'package:flutter_network_state/core/network_strategy.dart';
import 'package:flutter_network_state/manager/network_manager.dart';

/// A [ChangeNotifier] that wraps [NetworkManager] and exposes the current
/// [NetworkState] as a listenable property.
///
/// Drop this into `ChangeNotifierProvider` or any widget that consumes
/// [ChangeNotifier]:
///
/// ```dart
/// // Setup
/// ChangeNotifierProvider(
///   create: (_) => NetworkNotifier(networkManager),
///   child: MyApp(),
/// );
///
/// // Consume in widget
/// final notifier = context.watch<NetworkNotifier>();
/// switch (notifier.state) {
///   case Loading() => CircularProgressIndicator(),
///   case Success() => Text('${notifier.state}'),
///   case Offline() => Text('You are offline'),
///   // ...
/// }
/// ```
class NetworkNotifier extends ChangeNotifier {
  /// Creates a [NetworkNotifier] bound to the given [NetworkManager].
  ///
  /// Automatically subscribes to the manager's [stateStream].
  NetworkNotifier(this._manager) {
    _subscription = _manager.stateStream.listen((state) {
      _state = state;
      notifyListeners();
    });
  }

  final NetworkManager _manager;
  StreamSubscription<NetworkState>? _subscription;

  NetworkState _state = const Idle();

  /// The current [NetworkState].
  NetworkState get state => _state;

  /// Shorthand: whether the device is online.
  bool get isOnline => _manager.isOnline;

  /// Shorthand: number of queued requests.
  int get queuedRequests => _manager.queue.length;

  /// The underlying [NetworkManager] for advanced operations.
  NetworkManager get manager => _manager;

  /// Execute a request and automatically notify listeners as state changes.
  ///
  /// ```dart
  /// final user = await notifier.request(
  ///   () => api.getUser(),
  ///   cacheKey: 'user',
  ///   strategy: CacheFirst(),
  /// );
  /// ```
  Future<T?> request<T>(
    Future<T> Function() requestFn, {
    String? cacheKey,
    NetworkStrategy? strategy,
    Duration? cacheTtl,
  }) async {
    _state = const Loading();
    notifyListeners();

    try {
      final data = await _manager.request<T>(
        requestFn,
        cacheKey: cacheKey,
        strategy: strategy,
        cacheTtl: cacheTtl,
      );
      _state = Success<T>(data);
      notifyListeners();
      return data;
    } catch (e) {
      if (!_manager.isOnline) {
        _state = Offline(queuedRequests: _manager.queue.length);
      } else {
        _state = Error(e.toString(), exception: e);
      }
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
