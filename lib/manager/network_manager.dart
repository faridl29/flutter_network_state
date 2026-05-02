/// The central orchestrator of [flutter_network_state].
///
/// [NetworkManager] is the single entry-point that wires together:
/// - [NetworkStatusMonitor] — connectivity detection
/// - [CacheManager] — in-memory caching with TTL
/// - [RequestQueue] — offline request queue
/// - [SyncEngine] — automatic sync on reconnect
///
/// It exposes a unified `stateStream` and a `request<T>()` API that
/// applies [NetworkStrategy] logic transparently.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_network_state/cache/cache_manager.dart';
import 'package:flutter_network_state/core/logger.dart';
import 'package:flutter_network_state/core/network_state.dart';
import 'package:flutter_network_state/core/network_status.dart';
import 'package:flutter_network_state/core/network_strategy.dart';
import 'package:flutter_network_state/core/retry_policy.dart';
import 'package:flutter_network_state/queue/request_queue.dart';
import 'package:flutter_network_state/sync/sync_engine.dart';

/// Configuration for [NetworkManager].
class NetworkManagerConfig {
  const NetworkManagerConfig({
    this.defaultStrategy = const NetworkFirst(),
    this.defaultCacheTtl = const Duration(minutes: 5),
    this.retryPolicy = const RetryPolicy(),
    this.autoStart = true,
  });

  /// Default strategy when none is specified on individual requests.
  final NetworkStrategy defaultStrategy;

  /// Default TTL for cached entries.
  final Duration defaultCacheTtl;

  /// Default retry policy for queued requests.
  final RetryPolicy retryPolicy;

  /// Whether to start listening for connectivity automatically on creation.
  final bool autoStart;
}

/// The primary API surface of the plugin.
///
/// ```dart
/// final manager = NetworkManager();
///
/// manager.stateStream.listen((state) {
///   switch (state) {
///     case Loading()  => showSpinner();
///     case Offline()  => showBanner();
///     case Syncing()  => showSyncProgress(state.progress);
///     case Success()  => showData(state.data);
///     case Error()    => showError(state.message);
///     case Idle()     => hideIndicators();
///   }
/// });
///
/// final user = await manager.request(
///   () => api.getUser(),
///   cacheKey: 'user',
///   strategy: CacheFirst(),
/// );
/// ```
class NetworkManager {
  /// Creates a [NetworkManager] with sensible defaults.
  ///
  /// All sub-components can be overridden for testing or customization.
  NetworkManager({
    NetworkManagerConfig? config,
    NetworkStatusMonitor? monitor,
    CacheManager? cacheManager,
    RequestQueue? queue,
    SyncEngine? syncEngine,
    Connectivity? connectivity,
    NetworkLogger? logger,
  })  : _config = config ?? const NetworkManagerConfig(),
        _logger = logger ?? NetworkLogger.defaultLogger {
    // Initialize sub-components.
    _monitor = monitor ??
        NetworkStatusMonitor(
          connectivity: connectivity,
          logger: _logger,
        );

    _cache = cacheManager ??
        CacheManager(
          defaultTtl: _config.defaultCacheTtl,
          logger: _logger,
        );

    _queue = queue ?? RequestQueue(logger: _logger);

    _syncEngine = syncEngine ??
        SyncEngine(
          monitor: _monitor,
          queue: _queue,
          cacheManager: _cache,
          logger: _logger,
        );

    // Merge connectivity and sync states into a single stream.
    _setupStateStream();

    if (_config.autoStart) {
      initialize();
    }
  }

  final NetworkManagerConfig _config;
  final NetworkLogger _logger;

  late final NetworkStatusMonitor _monitor;
  late final CacheManager _cache;
  late final RequestQueue _queue;
  late final SyncEngine _syncEngine;

  final _stateController = StreamController<NetworkState>.broadcast();
  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  StreamSubscription<NetworkState>? _syncStateSub;

  bool _initialized = false;
  int _requestIdCounter = 0;

  // ---------------------------------------------------------------------------
  // Public accessors (for advanced use / Dio interceptor integration)
  // ---------------------------------------------------------------------------

  /// The connectivity monitor.
  NetworkStatusMonitor get monitor => _monitor;

  /// The cache manager.
  CacheManager get cache => _cache;

  /// The offline request queue.
  RequestQueue get queue => _queue;

  /// The sync engine.
  SyncEngine get syncEngine => _syncEngine;

  /// Whether the device is currently online.
  bool get isOnline => _monitor.isOnline;

  /// Current connectivity status.
  ConnectivityStatus get connectivityStatus => _monitor.currentStatus;

  // ---------------------------------------------------------------------------
  // State stream
  // ---------------------------------------------------------------------------

  /// Unified stream of [NetworkState] changes.
  ///
  /// This merges connectivity events, sync progress, and per-request
  /// lifecycle states into a single reactive stream.
  Stream<NetworkState> get stateStream => _stateController.stream;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialize the manager and start listening for connectivity.
  ///
  /// Called automatically if [NetworkManagerConfig.autoStart] is `true`.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _logger.info('NetworkManager: initializing');
    await _monitor.startListening();
    _syncEngine.start();
  }

  /// Dispose all resources. The manager must not be used after this.
  Future<void> dispose() async {
    _logger.info('NetworkManager: disposing');
    await _connectivitySub?.cancel();
    await _syncStateSub?.cancel();
    await _syncEngine.dispose();
    await _queue.dispose();
    await _monitor.dispose();
    await _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Request API
  // ---------------------------------------------------------------------------

  /// Execute a network request with strategy-based resolution.
  ///
  /// * [requestFn] — the async closure that performs the actual work.
  /// * [cacheKey] — optional key for caching the result.
  /// * [strategy] — how to resolve the request (defaults to config default).
  /// * [cacheTtl] — per-request TTL override.
  /// * [retryPolicy] — per-request retry override.
  /// * [queueIfOffline] — whether to enqueue when offline (default `true`).
  Future<T> request<T>(
    Future<T> Function() requestFn, {
    String? cacheKey,
    NetworkStrategy? strategy,
    Duration? cacheTtl,
    RetryPolicy? retryPolicy,
    bool queueIfOffline = true,
  }) async {
    final effectiveStrategy = strategy ?? _config.defaultStrategy;

    _logger.debug(
      'NetworkManager: request(strategy: $effectiveStrategy, '
      'cacheKey: $cacheKey)',
    );

    return switch (effectiveStrategy) {
      NetworkFirst() => _networkFirst<T>(
          requestFn,
          cacheKey: cacheKey,
          cacheTtl: cacheTtl,
          retryPolicy: retryPolicy,
          queueIfOffline: queueIfOffline,
        ),
      CacheFirst() => _cacheFirst<T>(
          requestFn,
          cacheKey: cacheKey,
          cacheTtl: cacheTtl,
          retryPolicy: retryPolicy,
          queueIfOffline: queueIfOffline,
        ),
      CacheOnly() => _cacheOnly<T>(cacheKey),
      NetworkOnly() => _networkOnly<T>(
          requestFn,
          retryPolicy: retryPolicy,
          queueIfOffline: queueIfOffline,
          cacheKey: cacheKey,
        ),
    };
  }

  /// Manually trigger sync of queued requests.
  Future<List<QueueProcessResult>> syncNow() => _syncEngine.syncNow();

  /// Invalidate a cache entry.
  void invalidateCache(String key) => _cache.invalidate(key);

  /// Clear all cached data.
  void clearCache() => _cache.clear();

  /// Clear the request queue.
  void clearQueue() => _queue.clear();

  // ---------------------------------------------------------------------------
  // Strategy implementations
  // ---------------------------------------------------------------------------

  Future<T> _networkFirst<T>(
    Future<T> Function() requestFn, {
    String? cacheKey,
    Duration? cacheTtl,
    RetryPolicy? retryPolicy,
    bool queueIfOffline = true,
  }) async {
    _emit(const Loading());

    try {
      final data = await requestFn();

      // Cache the result if a key was provided.
      if (cacheKey != null) {
        _cache.set<T>(cacheKey, data, ttl: cacheTtl);
      }

      _emit(Success<T>(data));
      return data;
    } catch (e, st) {
      _logger.warning('NetworkManager: network request failed — $e');

      // Fall back to cache.
      if (cacheKey != null) {
        final cached = _cache.get<T>(cacheKey);
        if (cached != null) {
          _logger.info('NetworkManager: falling back to cache for "$cacheKey"');
          _emit(Success<T>(cached, fromCache: true));
          return cached;
        }
      }

      // Queue for later if offline.
      if (queueIfOffline && !_monitor.isOnline) {
        _enqueueRequest<T>(requestFn, cacheKey, retryPolicy);
        _emit(Offline(queuedRequests: _queue.length));
      } else {
        _emit(Error(e.toString(), exception: e, stackTrace: st));
      }

      rethrow;
    }
  }

  Future<T> _cacheFirst<T>(
    Future<T> Function() requestFn, {
    String? cacheKey,
    Duration? cacheTtl,
    RetryPolicy? retryPolicy,
    bool queueIfOffline = true,
  }) async {
    // Try cache first.
    if (cacheKey != null) {
      final cached = _cache.get<T>(cacheKey);
      if (cached != null) {
        _logger.info('NetworkManager: cache hit for "$cacheKey"');
        _emit(Success<T>(cached, fromCache: true));
        return cached;
      }
    }

    // Cache miss — fall through to network.
    return _networkFirst<T>(
      requestFn,
      cacheKey: cacheKey,
      cacheTtl: cacheTtl,
      retryPolicy: retryPolicy,
      queueIfOffline: queueIfOffline,
    );
  }

  Future<T> _cacheOnly<T>(String? cacheKey) async {
    if (cacheKey == null) {
      const msg = 'CacheOnly strategy requires a cacheKey';
      _emit(const Error(msg, isRetryable: false));
      throw StateError(msg);
    }

    final cached = _cache.get<T>(cacheKey);
    if (cached != null) {
      _emit(Success<T>(cached, fromCache: true));
      return cached;
    }

    const msg = 'Cache miss';
    _emit(const Error(msg, isRetryable: false));
    throw StateError('$msg: no entry for key "$cacheKey"');
  }

  Future<T> _networkOnly<T>(
    Future<T> Function() requestFn, {
    RetryPolicy? retryPolicy,
    bool queueIfOffline = true,
    String? cacheKey,
  }) async {
    _emit(const Loading());

    try {
      final data = await requestFn();
      _emit(Success<T>(data));
      return data;
    } catch (e, st) {
      if (queueIfOffline && !_monitor.isOnline) {
        _enqueueRequest<T>(requestFn, cacheKey, retryPolicy);
        _emit(Offline(queuedRequests: _queue.length));
      } else {
        _emit(Error(e.toString(), exception: e, stackTrace: st));
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _enqueueRequest<T>(
    Future<T> Function() requestFn,
    String? cacheKey,
    RetryPolicy? retryPolicy,
  ) {
    final id = 'req_${++_requestIdCounter}_'
        '${DateTime.now().millisecondsSinceEpoch}';
    _queue.enqueue(
      QueuedRequest(
        id: id,
        execute: () => requestFn(),
        cacheKey: cacheKey,
        retryPolicy: retryPolicy ?? _config.retryPolicy,
      ),
    );
    _logger.info('NetworkManager: queued request "$id" for later');
  }

  void _setupStateStream() {
    // Forward connectivity changes.
    _connectivitySub = _monitor.statusStream.listen((status) {
      if (status == ConnectivityStatus.offline) {
        _emit(Offline(queuedRequests: _queue.length));
      }
    });

    // Forward sync engine states.
    _syncStateSub = _syncEngine.stateStream.listen((state) {
      _emit(state);
    });
  }

  void _emit(NetworkState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}
