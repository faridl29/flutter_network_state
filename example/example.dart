// ignore_for_file: avoid_print

/// Comprehensive example demonstrating all features of [flutter_network_state].
///
/// This example shows:
/// 1. Basic setup with NetworkManager
/// 2. Strategy-based requests (NetworkFirst, CacheFirst, etc.)
/// 3. Dio interceptor integration
/// 4. Bloc-style state management
/// 5. Queue and sync lifecycle
library;

import 'package:dio/dio.dart';
import 'package:flutter_network_state/flutter_network_state.dart';

// =============================================================================
// 1. BASIC USAGE
// =============================================================================

/// Demonstrates the simplest possible setup.
Future<void> basicUsage() async {
  // Create the manager — it starts listening for connectivity automatically.
  final manager = NetworkManager();

  // Listen to unified state stream.
  manager.stateStream.listen((state) {
    switch (state) {
      case Idle():
        print('✅ Idle');
      case Loading():
        print('⏳ Loading...');
      case Offline():
        print('📴 Offline (${state.queuedRequests} queued)');
      case Syncing():
        print('🔄 Syncing ${(state.progress * 100).toStringAsFixed(0)}%');
      case Success():
        print('🎉 Success: ${state.data}');
      case Error():
        print('❌ Error: ${state.message}');
    }
  });

  // Make a request with CacheFirst strategy.
  try {
    final user = await manager.request(
      () => _fakeApiCall('/users/1'),
      cacheKey: 'user_1',
      strategy: const CacheFirst(),
    );
    print('Got user: $user');
  } catch (e) {
    print('Request failed: $e');
  }

  // Clean up.
  await manager.dispose();
}

// =============================================================================
// 2. DIO INTEGRATION
// =============================================================================

/// Demonstrates plugging into an existing Dio instance.
Future<void> dioIntegration() async {
  final manager = NetworkManager(
    config: const NetworkManagerConfig(
      defaultStrategy: NetworkFirst(),
      defaultCacheTtl: Duration(minutes: 10),
      retryPolicy: RetryPolicy(
        maxRetries: 3,
        backoff: ExponentialBackoff(
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 15),
        ),
      ),
    ),
  );

  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

  // Attach the interceptor.
  dio.interceptors.add(
    NetworkDioInterceptor(
      monitor: manager.monitor,
      queue: manager.queue,
      config: const DioInterceptorConfig(
        retryPolicy: RetryPolicy(maxRetries: 2),
        queueWhenOffline: true,
        logRequests: true,
        logResponses: true,
      ),
    ),
  );

  // Now use Dio normally — retries and queueing happen automatically.
  try {
    final response = await dio.get<Map<String, dynamic>>('/users/1');
    print('Response: ${response.data}');
  } on DioException catch (e) {
    print('Dio error: ${e.message}');
  }

  await manager.dispose();
}

// =============================================================================
// 3. BLOC-STYLE INTEGRATION
// =============================================================================

/// Demonstrates Bloc-friendly usage with [executeAndEmit].
///
/// In a real app, this would be a Cubit or Bloc event handler.
Future<void> blocStyleIntegration() async {
  final manager = NetworkManager();

  // Simulated Cubit emit function.
  void emit(NetworkState state) {
    print('Cubit state → $state');
  }

  // Use the Bloc extension.
  final user = await manager.executeAndEmit(
    () => _fakeApiCall('/users/1'),
    emit: emit,
    cacheKey: 'user_1',
    strategy: const CacheFirst(),
  );

  print('Cubit received: $user');
  await manager.dispose();
}

// =============================================================================
// 4. CUSTOM CACHE STORE
// =============================================================================

/// Demonstrates providing a custom cache store.
Future<void> customCacheStore() async {
  // You could implement a Hive-backed or SharedPreferences-backed store.
  final customStore = InMemoryCacheStore();

  final manager = NetworkManager(
    cacheManager: CacheManager(
      store: customStore,
      defaultTtl: const Duration(hours: 1),
    ),
  );

  await manager.request(
    () => _fakeApiCall('/config'),
    cacheKey: 'app_config',
    strategy: const CacheFirst(),
    cacheTtl: const Duration(hours: 24),
  );

  // Later: read from cache only (no network).
  try {
    final config = await manager.request<Map<String, dynamic>>(
      () => throw Exception('should not be called'),
      cacheKey: 'app_config',
      strategy: const CacheOnly(),
    );
    print('Cached config: $config');
  } catch (e) {
    print('Cache miss: $e');
  }

  await manager.dispose();
}

// =============================================================================
// 5. MANUAL QUEUE + SYNC
// =============================================================================

/// Demonstrates manual queue management and forced sync.
Future<void> queueAndSync() async {
  final manager = NetworkManager(
    config: const NetworkManagerConfig(autoStart: false),
  );

  // Initialize manually.
  await manager.initialize();

  // Manually enqueue a request.
  manager.queue.enqueue(
    QueuedRequest(
      id: 'update_profile',
      execute: () => _fakeApiCall('/users/1', method: 'PUT'),
      cacheKey: 'user_1',
      retryPolicy: const RetryPolicy(
        maxRetries: 5,
        backoff: ExponentialBackoff(baseDelay: Duration(seconds: 2)),
      ),
    ),
  );

  print('Queue size: ${manager.queue.length}');

  // Force sync now (even if connectivity hasn't changed).
  final results = await manager.syncNow();
  for (final r in results) {
    print('${r.request.id}: ${r.isSuccess ? "✓" : "✗"}');
  }

  await manager.dispose();
}

// =============================================================================
// 6. CUSTOM LOGGER
// =============================================================================

/// Demonstrates plugging in a custom logger.
Future<void> customLogger() async {
  final logger = NetworkLogger.custom(
    (level, message) {
      // Forward to your logging framework (e.g. Crashlytics, Sentry).
      print('[${level.name}] $message');
    },
    minLevel: LogLevel.info, // Suppress debug noise.
  );

  final manager = NetworkManager(logger: logger);

  await manager.request(
    () => _fakeApiCall('/health'),
    strategy: const NetworkOnly(),
  );

  await manager.dispose();
}

// =============================================================================
// 7. ALL STRATEGIES SHOWCASE
// =============================================================================

/// Demonstrates every strategy in action.
Future<void> strategyShowcase() async {
  final manager = NetworkManager();

  // NetworkFirst — try network, fall back to cache.
  await _tryRequest(manager, 'NetworkFirst', const NetworkFirst());

  // CacheFirst — try cache, fall back to network.
  await _tryRequest(manager, 'CacheFirst', const CacheFirst());

  // CacheOnly — cache or fail.
  await _tryRequest(manager, 'CacheOnly', const CacheOnly());

  // NetworkOnly — network or fail, no caching.
  await _tryRequest(manager, 'NetworkOnly', const NetworkOnly());

  await manager.dispose();
}

Future<void> _tryRequest(
  NetworkManager manager,
  String label,
  NetworkStrategy strategy,
) async {
  try {
    final data = await manager.request(
      () => _fakeApiCall('/data'),
      cacheKey: 'demo',
      strategy: strategy,
    );
    print('$label → $data');
  } catch (e) {
    print('$label → Error: $e');
  }
}

// =============================================================================
// Helpers
// =============================================================================

/// Simulates an API call.
Future<Map<String, dynamic>> _fakeApiCall(
  String path, {
  String method = 'GET',
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return {
    'path': path,
    'method': method,
    'timestamp': DateTime.now().toIso8601String(),
  };
}

// =============================================================================
// Entry point
// =============================================================================

void main() async {
  print('═══════════════════════════════════════════');
  print('  flutter_network_state — Example');
  print('═══════════════════════════════════════════\n');

  print('--- 1. Basic Usage ---');
  await basicUsage();

  print('\n--- 2. Dio Integration ---');
  await dioIntegration();

  print('\n--- 3. Bloc-Style Integration ---');
  await blocStyleIntegration();

  print('\n--- 4. Custom Cache Store ---');
  await customCacheStore();

  print('\n--- 5. Queue & Sync ---');
  await queueAndSync();

  print('\n--- 6. Custom Logger ---');
  await customLogger();

  print('\n--- 7. Strategy Showcase ---');
  await strategyShowcase();

  print('\n✅ All examples complete.');
}
