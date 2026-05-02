/// A convenience widget that rebuilds based on [NetworkState] changes.
///
/// Wraps a [StreamBuilder] around [NetworkManager.stateStream] and provides
/// a builder callback that receives the current [NetworkState].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_network_state/core/network_state.dart';
import 'package:flutter_network_state/manager/network_manager.dart';

/// A widget that rebuilds whenever [NetworkManager] emits a new state.
///
/// ```dart
/// NetworkBuilder(
///   manager: networkManager,
///   builder: (context, state) {
///     return switch (state) {
///       Idle()    => Text('Ready'),
///       Loading() => CircularProgressIndicator(),
///       Offline() => OfflineBanner(queued: state.queuedRequests),
///       Syncing() => LinearProgressIndicator(value: state.progress),
///       Success() => DataView(data: state.data),
///       Error()   => ErrorView(message: state.message),
///     };
///   },
/// )
/// ```
class NetworkBuilder extends StatelessWidget {
  /// Creates a [NetworkBuilder].
  const NetworkBuilder({
    super.key,
    required this.manager,
    required this.builder,
    this.initialState,
  });

  /// The [NetworkManager] whose state stream to listen to.
  final NetworkManager manager;

  /// Builder called with the current [NetworkState].
  final Widget Function(BuildContext context, NetworkState state) builder;

  /// Optional initial state. Defaults to [Idle].
  final NetworkState? initialState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NetworkState>(
      stream: manager.stateStream,
      initialData: initialState ?? const Idle(),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const Idle();
        return builder(context, state);
      },
    );
  }
}

/// A widget that shows different children based on online/offline status.
///
/// ```dart
/// ConnectivityBuilder(
///   manager: networkManager,
///   onlineBuilder: (context) => MyApp(),
///   offlineBuilder: (context, queuedCount) => OfflineScreen(
///     queuedRequests: queuedCount,
///   ),
/// )
/// ```
class ConnectivityBuilder extends StatelessWidget {
  /// Creates a [ConnectivityBuilder].
  const ConnectivityBuilder({
    super.key,
    required this.manager,
    required this.onlineBuilder,
    required this.offlineBuilder,
  });

  /// The [NetworkManager] to observe.
  final NetworkManager manager;

  /// Builder shown when the device is online.
  final Widget Function(BuildContext context) onlineBuilder;

  /// Builder shown when the device is offline.
  /// Receives the number of queued requests.
  final Widget Function(BuildContext context, int queuedRequests)
      offlineBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NetworkState>(
      stream: manager.stateStream,
      initialData: const Idle(),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state is Offline) {
          return offlineBuilder(context, state.queuedRequests);
        }
        return onlineBuilder(context);
      },
    );
  }
}
