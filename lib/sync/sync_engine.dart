/// Sync engine that orchestrates connectivity changes and the offline
/// request queue.
library;

import 'dart:async';

import 'package:flutter_network_state/cache/cache_manager.dart';
import 'package:flutter_network_state/core/logger.dart';
import 'package:flutter_network_state/core/network_state.dart';
import 'package:flutter_network_state/core/network_status.dart';
import 'package:flutter_network_state/queue/request_queue.dart';

/// Listens to [NetworkStatusMonitor] and triggers [RequestQueue] processing
/// whenever connectivity is restored.
class SyncEngine {
  SyncEngine({
    required NetworkStatusMonitor monitor,
    required RequestQueue queue,
    CacheManager? cacheManager,
    NetworkLogger? logger,
  })  : _monitor = monitor,
        _queue = queue,
        _cacheManager = cacheManager,
        _logger = logger ?? NetworkLogger.defaultLogger;

  final NetworkStatusMonitor _monitor;
  final RequestQueue _queue;
  final CacheManager? _cacheManager;
  final NetworkLogger _logger;

  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  final _stateController = StreamController<NetworkState>.broadcast();
  bool _isSyncing = false;

  Stream<NetworkState> get stateStream => _stateController.stream;
  bool get isSyncing => _isSyncing;

  void start() {
    if (_connectivitySub != null) return;
    _logger.info('SyncEngine: started');
    _connectivitySub = _monitor.statusStream.listen(_onConnectivityChanged);
    if (!_monitor.isOnline) {
      _emit(Offline(queuedRequests: _queue.length));
    }
  }

  Future<List<QueueProcessResult>> syncNow() async {
    if (_isSyncing) return [];
    return _processQueue();
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _stateController.close();
  }

  void _onConnectivityChanged(ConnectivityStatus status) {
    _logger.info('SyncEngine: connectivity → $status');
    switch (status) {
      case ConnectivityStatus.offline:
        _emit(Offline(queuedRequests: _queue.length));
      case ConnectivityStatus.online:
        if (_queue.isEmpty) {
          _emit(const Idle());
        } else {
          _processQueue();
        }
    }
  }

  Future<List<QueueProcessResult>> _processQueue() async {
    _isSyncing = true;
    final total = _queue.length;
    _emit(Syncing(totalRequests: total, completedRequests: 0));

    final results = await _queue.processQueue(
      onProgress: (completed, total) {
        _emit(Syncing(totalRequests: total, completedRequests: completed));
      },
    );

    if (_cacheManager != null) {
      for (final r in results) {
        if (r.isSuccess && r.request.cacheKey != null) {
          _cacheManager!.set(r.request.cacheKey!, r.data);
        }
      }
    }

    _isSyncing = false;
    _emit(const Idle());
    return results;
  }

  void _emit(NetworkState state) {
    if (!_stateController.isClosed) _stateController.add(state);
  }
}
