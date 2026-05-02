/// Reactive network connectivity monitor built on top of `connectivity_plus`.
///
/// Provides a [Stream<ConnectivityStatus>] that reflects the device's current
/// network reachability. This is consumed internally by [NetworkManager] and
/// [SyncEngine] — most users don't need to interact with it directly.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_network_state/core/logger.dart';

/// Simplified connectivity status.
enum ConnectivityStatus {
  /// Device has a working network connection (wifi, mobile, ethernet, etc.).
  online,

  /// Device has no network connection.
  offline,
}

/// Monitors network connectivity and exposes a reactive stream of
/// [ConnectivityStatus] changes.
///
/// Usage:
/// ```dart
/// final monitor = NetworkStatusMonitor();
/// monitor.statusStream.listen((status) {
///   print('Connectivity: $status');
/// });
/// ```
class NetworkStatusMonitor {
  /// Creates a [NetworkStatusMonitor].
  ///
  /// An optional [Connectivity] instance can be injected for testing.
  NetworkStatusMonitor({
    Connectivity? connectivity,
    NetworkLogger? logger,
  })  : _connectivity = connectivity ?? Connectivity(),
        _logger = logger ?? NetworkLogger.defaultLogger;

  final Connectivity _connectivity;
  final NetworkLogger _logger;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Controller that fans out connectivity changes.
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  /// The last known connectivity status.
  ConnectivityStatus _lastStatus = ConnectivityStatus.online;

  /// Whether the monitor has been started.
  bool _isListening = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Reactive stream of connectivity changes.
  ///
  /// The stream only emits when the status actually *changes* (deduped).
  Stream<ConnectivityStatus> get statusStream => _controller.stream;

  /// The last known connectivity status. Defaults to [ConnectivityStatus.online]
  /// until the first check completes.
  ConnectivityStatus get currentStatus => _lastStatus;

  /// Whether the device is currently online.
  bool get isOnline => _lastStatus == ConnectivityStatus.online;

  /// Start listening for connectivity changes.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> startListening() async {
    if (_isListening) return;
    _isListening = true;

    _logger.info('NetworkStatusMonitor: starting connectivity listener');

    // Check initial status.
    try {
      final results = await _connectivity.checkConnectivity();
      _processResults(results);
    } catch (e) {
      _logger.warning(
        'NetworkStatusMonitor: initial check failed, assuming online — $e',
      );
    }

    // Listen for ongoing changes.
    _subscription = _connectivity.onConnectivityChanged.listen(
      _processResults,
      onError: (Object error) {
        _logger.error('NetworkStatusMonitor: stream error — $error');
      },
    );
  }

  /// Perform a one-shot connectivity check and update [currentStatus].
  Future<ConnectivityStatus> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _processResults(results);
    } catch (e) {
      _logger.warning('NetworkStatusMonitor: checkNow failed — $e');
    }
    return _lastStatus;
  }

  /// Release resources. After calling this the monitor must not be reused.
  Future<void> dispose() async {
    _logger.info('NetworkStatusMonitor: disposing');
    await _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    await _controller.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _processResults(List<ConnectivityResult> results) {
    final status = _mapResults(results);
    if (status != _lastStatus) {
      _lastStatus = status;
      _logger.info('NetworkStatusMonitor: status changed → $status');
      if (!_controller.isClosed) {
        _controller.add(status);
      }
    }
  }

  /// Maps a list of [ConnectivityResult] to a single [ConnectivityStatus].
  ///
  /// If *any* result indicates a connection, we consider the device online.
  ConnectivityStatus _mapResults(List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectivityStatus.offline;

    final hasConnection = results.any(
      (r) => r != ConnectivityResult.none,
    );

    return hasConnection
        ? ConnectivityStatus.online
        : ConnectivityStatus.offline;
  }
}
