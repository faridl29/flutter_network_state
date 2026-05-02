/// # flutter_network_state
///
/// A network-aware state management and request orchestration engine for
/// Flutter.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:flutter_network_state/flutter_network_state.dart';
///
/// final manager = NetworkManager();
///
/// manager.stateStream.listen((state) {
///   switch (state) {
///     case Idle()    => print('Idle');
///     case Loading() => print('Loading...');
///     case Offline() => print('Offline (${state.queuedRequests} queued)');
///     case Syncing() => print('Syncing ${state.progress * 100}%');
///     case Success() => print('Data: ${state.data}');
///     case Error()   => print('Error: ${state.message}');
///   }
/// });
///
/// final user = await manager.request(
///   () => api.getUser(),
///   cacheKey: 'user',
///   strategy: CacheFirst(),
/// );
/// ```
library flutter_network_state;

// Core
export 'core/internet_checker.dart';
export 'core/logger.dart';
export 'core/network_state.dart';
export 'core/network_status.dart';
export 'core/network_strategy.dart';
export 'core/retry_policy.dart';

// Cache
export 'cache/cache_manager.dart';

// Queue
export 'queue/persistent_queue_store.dart';
export 'queue/request_queue.dart';

// Sync
export 'sync/sync_engine.dart';

// Manager
export 'manager/network_manager.dart';

// Dio integration
export 'dio/dio_interceptor.dart';

// Widgets
export 'widgets/network_builder.dart';

// Extensions
export 'extensions/bloc_extension.dart';
export 'extensions/cubit_extension.dart';
export 'extensions/provider_extension.dart';
export 'extensions/riverpod_extension.dart';

