<p align="center">
  <h1 align="center">flutter_network_state</h1>
  <p align="center">
    A network-aware state management and request orchestration engine for Flutter.
    <br />
    <em>Not just another connectivity checker.</em>
  </p>
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_network_state"><img src="https://img.shields.io/pub/v/flutter_network_state.svg" alt="pub version"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3-0175C2.svg?logo=dart" alt="Dart 3"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.10+-02569B.svg?logo=flutter" alt="Flutter"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
</p>

---

## What is this?

`flutter_network_state` is a **decision engine** that sits between your app and the network. It unifies:

- 🌐 **Online/Offline detection** — stream-based, always reactive
- 🔍 **Real internet check** — DNS lookup verification, not just interface detection
- 🎯 **Smart request strategies** — NetworkFirst, CacheFirst, CacheOnly, NetworkOnly
- 📦 **In-memory caching** — with TTL and pluggable storage
- 📋 **Offline request queue** — failed requests are queued and replayed automatically
- 🔄 **Automatic sync** — queue drains when connectivity is restored
- 🔌 **Dio interceptor** — drop-in auto-retry and offline queueing
- 🧱 **Reactive widgets** — `NetworkBuilder` and `ConnectivityBuilder` for instant UI binding
- 🧩 **State management ready** — built-in support for Provider, Cubit, Bloc, and Riverpod
- 🔁 **Retry policies** — exponential, linear, constant backoff with jitter

> Think of it as **Dio + Bloc + Offline Sync + Connectivity** in one clean abstraction.

---

## Getting Started

### Installation

```yaml
dependencies:
  flutter_network_state: ^1.0.0
```

```bash
flutter pub get
```

### Minimal Example

```dart
import 'package:flutter_network_state/flutter_network_state.dart';

final manager = NetworkManager();

// Listen to state changes
manager.stateStream.listen((state) {
  switch (state) {
    case Idle()    => print('Ready');
    case Loading() => print('Loading...');
    case Offline() => print('Offline (${state.queuedRequests} queued)');
    case Syncing() => print('Syncing ${(state.progress * 100).toStringAsFixed(0)}%');
    case Success() => print('Data: ${state.data}');
    case Error()   => print('Error: ${state.message}');
  }
});

// Make a request with strategy
final user = await manager.request(
  () => api.getUser(),
  cacheKey: 'user',
  strategy: CacheFirst(),
);
```

That's it. The manager handles connectivity detection, caching, offline queueing, and automatic sync — all behind that single `request()` call.

---

## Core Concepts

### Network States

All states are Dart 3 `sealed` classes — fully exhaustive in `switch`:

| State | Description |
|---|---|
| `Idle` | No operation in progress |
| `Loading` | A request is executing |
| `Offline` | Device has no connectivity. Includes `queuedRequests` count |
| `Syncing` | Queue is being replayed after reconnect. Includes `progress` (0.0–1.0) |
| `Success<T>` | Request completed. Contains `data` and `fromCache` flag |
| `Error` | Request failed. Contains `message`, `exception`, and `isRetryable` |

### Request Strategies

Control how each request is resolved:

| Strategy | Behavior |
|---|---|
| `NetworkFirst()` | Try network → fall back to cache on failure *(default)* |
| `CacheFirst()` | Try cache → fall back to network on miss or expiry |
| `CacheOnly()` | Only use cache — never hits the network |
| `NetworkOnly()` | Only use network — never reads or writes cache |

```dart
// Cache-first with custom TTL
final config = await manager.request(
  () => api.getAppConfig(),
  cacheKey: 'app_config',
  strategy: CacheFirst(),
  cacheTtl: Duration(hours: 1),
);

// Network-only for mutations
await manager.request(
  () => api.updateProfile(data),
  strategy: NetworkOnly(),
);
```

---

## State Management Integration

`flutter_network_state` ships with built-in support for the most popular Flutter state management solutions — **without adding any of them as dependencies**. Pick the one you use:

### Provider (ChangeNotifier)

Use `NetworkNotifier`, a ready-made `ChangeNotifier`:

```dart
// Setup
ChangeNotifierProvider(
  create: (_) => NetworkNotifier(networkManager),
  child: MyApp(),
);

// In your widget
class UserPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<NetworkNotifier>();

    return switch (notifier.state) {
      Idle()    => Text('Tap to load'),
      Loading() => CircularProgressIndicator(),
      Offline() => Text('Offline (${(notifier.state as Offline).queuedRequests} queued)'),
      Success() => Text('Hello, ${(notifier.state as Success).data}'),
      Error()   => Text('Error: ${(notifier.state as Error).message}'),
      _         => SizedBox.shrink(),
    };
  }
}

// Trigger a request
final notifier = context.read<NetworkNotifier>();
await notifier.request(
  () => api.getUser(),
  cacheKey: 'user',
  strategy: CacheFirst(),
);
```

### Cubit (No flutter_bloc needed)

Use `NetworkCubit`, a lightweight Cubit-like base class:

```dart
class UserCubit extends NetworkCubit {
  UserCubit(NetworkManager manager) : super(manager);

  Future<void> loadUser() async {
    await executeRequest(
      () => api.getUser(),
      cacheKey: 'user',
      strategy: CacheFirst(),
    );
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    await executeRequest(
      () => api.updateProfile(data),
      strategy: NetworkOnly(),
    );
  }
}

// Usage
final cubit = UserCubit(networkManager);

// Listen to state changes
cubit.stream.listen((state) {
  switch (state) {
    case Success<User>() => print('Got user: ${state.data.name}');
    case Loading()       => print('Loading...');
    case Offline()       => print('Offline');
    case Error()         => print('Error: ${state.message}');
    _                    => null;
  }
});

await cubit.loadUser();

// Don't forget to close
await cubit.close();
```

### Bloc (flutter_bloc)

If you already use `flutter_bloc`, use the `executeAndEmit()` extension:

```dart
class UserCubit extends Cubit<NetworkState> {
  UserCubit(this._manager) : super(const Idle());
  final NetworkManager _manager;

  Future<void> loadUser() async {
    await _manager.executeAndEmit(
      () => api.getUser(),
      emit: emit,
      cacheKey: 'user',
      strategy: CacheFirst(),
    );
  }
}

// Or bind the global connectivity state stream
class ConnectivityCubit extends Cubit<NetworkState> {
  ConnectivityCubit(this._manager) : super(const Idle());
  final NetworkManager _manager;
  late final StreamSubscription _sub;

  void init() {
    _sub = _manager.bindToEmit(emit);
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
```

### Riverpod

Use `NetworkStateNotifier` with Riverpod providers:

```dart
// 1. Provide the NetworkManager
final networkManagerProvider = Provider<NetworkManager>((ref) {
  final manager = NetworkManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

// 2. Stream the global connectivity state
final networkStateProvider = StreamProvider<NetworkState>((ref) {
  return ref.watch(networkManagerProvider).stateStream;
});

// 3. Create feature-specific notifiers
final userProvider = Provider<NetworkStateNotifier>((ref) {
  final notifier = ref.watch(networkManagerProvider).createNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

// In your widget
class UserPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userNotifier = ref.watch(userProvider);

    return switch (userNotifier.state) {
      Loading() => CircularProgressIndicator(),
      Success() => Text('${(userNotifier.state as Success).data}'),
      Offline() => Text('Offline'),
      Error()   => Text('Error'),
      _         => ElevatedButton(
        onPressed: () => ref.read(userProvider).execute(
          () => api.getUser(),
          cacheKey: 'user',
          strategy: CacheFirst(),
        ),
        child: Text('Load User'),
      ),
    };
  }
}
```

### Stream Transformer (Any architecture)

Turn any `Stream<T>` into `Stream<NetworkState>`:

```dart
final stateStream = myDataStream.asNetworkStates();
// Each emission becomes Success<T>, errors become Error
```

---

## Dio Integration

Drop the interceptor into any existing `Dio` instance:

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

dio.interceptors.add(
  NetworkDioInterceptor(
    monitor: manager.monitor,
    queue: manager.queue,
    config: DioInterceptorConfig(
      retryPolicy: RetryPolicy(
        maxRetries: 3,
        backoff: ExponentialBackoff(baseDelay: Duration(seconds: 1)),
      ),
      queueWhenOffline: true,
      logRequests: true,
      logResponses: true,
    ),
  ),
);
```

The interceptor automatically:
- ✅ Retries transient failures (timeouts, 500s, 502s, 503s, 429s)
- ✅ Queues requests when the device is offline
- ✅ Replays queued requests when connectivity is restored

---

## Retry Policies

Every retry policy supports configurable backoff:

```dart
// Exponential backoff with jitter (default)
RetryPolicy(
  maxRetries: 3,
  backoff: ExponentialBackoff(
    baseDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    withJitter: true, // ±25% to prevent thundering herd
  ),
);

// Constant delay
RetryPolicy(
  maxRetries: 5,
  backoff: ConstantBackoff(duration: Duration(seconds: 2)),
);

// Linear backoff
RetryPolicy(
  maxRetries: 4,
  backoff: LinearBackoff(baseDelay: Duration(seconds: 1)),
);

// Disable retries
RetryPolicy.none;
```

Custom retry predicate:

```dart
RetryPolicy(
  maxRetries: 3,
  shouldRetry: (error, attempt) {
    return error is TimeoutException;
  },
);
```

---

## Cache Management

### Basic operations

```dart
// Store
manager.cache.set('key', myData, ttl: Duration(hours: 1));

// Retrieve (null if expired)
final data = manager.cache.get<MyModel>('key');

// Check existence (respects TTL)
manager.cache.has('key');

// Invalidate
manager.invalidateCache('key');

// Clear all
manager.clearCache();
```

### Custom storage backend

Implement `CacheStore` to use Hive, Isar, SharedPreferences, or any persistence layer:

```dart
class HiveCacheStore implements CacheStore {
  final Box _box;
  HiveCacheStore(this._box);

  @override
  dynamic get(String key) => _box.get(key);
  @override
  void set(String key, dynamic value) => _box.put(key, value);
  @override
  void remove(String key) => _box.delete(key);
  @override
  void clear() => _box.clear();
  @override
  bool containsKey(String key) => _box.containsKey(key);
}

final manager = NetworkManager(
  cacheManager: CacheManager(store: HiveCacheStore(box)),
);
```

---

## Offline Queue & Sync

### Automatic flow

1. Request fails while offline → automatically queued
2. Device reconnects → `SyncEngine` drains the queue
3. State stream emits `Syncing(progress)` → UI shows progress
4. All done → state returns to `Idle`

### Manual queue operations

```dart
// Enqueue manually
manager.queue.enqueue(
  QueuedRequest(
    id: 'update_profile',
    execute: () => api.updateProfile(data),
    retryPolicy: RetryPolicy(maxRetries: 5),
  ),
);

// Inspect
print('Pending: ${manager.queue.length}');

// Force sync
final results = await manager.syncNow();

// Clear
manager.clearQueue();
```

### Persistent queue (survives app restarts)

By default, the queue is in-memory and lost on restart. For persistence, use `PersistentQueueStore`:

```dart
import 'package:path_provider/path_provider.dart';

// 1. Create the persistent store
final appDir = await getApplicationDocumentsDirectory();
final store = PersistentQueueStore(
  directory: appDir,
  executor: (request) async {
    // This callback replays persisted requests using your HTTP client
    final response = await dio.request(
      request.url,
      options: Options(method: request.method, headers: request.headers),
      data: request.body,
    );
    return response.data;
  },
);
await store.initialize(); // Load queue from disk

// 2. Inject into NetworkManager
final manager = NetworkManager(
  queue: RequestQueue(store: store),
);

// 3. Enqueue serializable requests (persisted to disk)
await store.enqueueSerializable(SerializableRequest(
  id: 'update_profile',
  method: 'PUT',
  url: 'https://api.example.com/profile',
  headers: {'Authorization': 'Bearer $token'},
  body: jsonEncode({'name': 'John'}),
  cacheKey: 'profile',
  maxRetries: 5,
));

// Queue survives app restarts — requests replay automatically on reconnect
```

### Hive queue store

For apps already using Hive, see [`doc/hive_queue_store.md`](doc/hive_queue_store.md) — copy the implementation into your project:

```yaml
# pubspec.yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0
```

```dart
import 'package:hive_flutter/hive_flutter.dart';

await Hive.initFlutter();
final box = await Hive.openBox<String>('network_queue');

final store = HiveQueueStore(
  box: box,
  executor: (req) async {
    return await dio.request(
      req.url,
      options: Options(method: req.method, headers: req.headers),
      data: req.body,
    );
  },
);

final manager = NetworkManager(queue: RequestQueue(store: store));
```

### sqflite queue store

For apps using SQLite, see [`doc/sqflite_queue_store.md`](doc/sqflite_queue_store.md) — copy the implementation into your project:

```yaml
# pubspec.yaml
dependencies:
  sqflite: ^2.3.0
  path: ^1.8.0
```

```dart
final store = await SqfliteQueueStore.open(
  executor: (req) async {
    return await dio.request(
      req.url,
      options: Options(method: req.method, headers: req.headers),
      data: req.body,
    );
  },
);

final manager = NetworkManager(queue: RequestQueue(store: store));

// Don't forget to close when done
await store.close();
```

> **Which one should I use?**
>
> | Store | Best for |
> |---|---|
> | `PersistentQueueStore` (built-in) | Simple apps, no extra dependencies |
> | `HiveQueueStore` | Apps already using Hive |
> | `SqfliteQueueStore` | Apps needing SQL queries or large queues |

---

## Logging

```dart
// Default — prints to console
final manager = NetworkManager();

// Silent
final manager = NetworkManager(logger: NetworkLogger.silent);

// Custom — forward to Crashlytics, Sentry, etc.
final manager = NetworkManager(
  logger: NetworkLogger.custom(
    (level, message) {
      FirebaseCrashlytics.instance.log('[$level] $message');
    },
    minLevel: LogLevel.warning,
  ),
);
```

---

## Configuration

```dart
final manager = NetworkManager(
  config: NetworkManagerConfig(
    defaultStrategy: NetworkFirst(),
    defaultCacheTtl: Duration(minutes: 5),
    retryPolicy: RetryPolicy(maxRetries: 3),
    autoStart: true,
  ),
);
```

---

## Real Internet Check

`connectivity_plus` only checks if a network **interface** is available — it doesn't verify actual internet access (captive portals, DNS failures, etc.). `InternetChecker` solves this:

```dart
final checker = InternetChecker();

// One-shot check
final isOnline = await checker.hasInternetAccess();
print('Internet: $isOnline');

// Periodic monitoring (emits only on change)
checker.startPeriodicCheck();
checker.statusStream.listen((isOnline) {
  print('Internet changed: $isOnline');
});

// Custom config
final checker = InternetChecker(
  config: InternetCheckerConfig(
    lookupAddresses: ['google.com', 'cloudflare.com'],
    timeout: Duration(seconds: 5),
    checkInterval: Duration(seconds: 15),
  ),
);
```

---

## Widgets

Drop-in widgets that rebuild automatically based on network state:

### NetworkBuilder

```dart
NetworkBuilder(
  manager: networkManager,
  builder: (context, state) {
    return switch (state) {
      Idle()    => Text('Ready'),
      Loading() => CircularProgressIndicator(),
      Offline() => Text('Offline (${state.queuedRequests} queued)'),
      Syncing() => LinearProgressIndicator(value: state.progress),
      Success() => Text('Data: ${state.data}'),
      Error()   => Text('Error: ${state.message}'),
    };
  },
)
```

### ConnectivityBuilder

```dart
ConnectivityBuilder(
  manager: networkManager,
  onlineBuilder: (context) => MyMainContent(),
  offlineBuilder: (context, queuedCount) => Column(
    children: [
      Icon(Icons.wifi_off),
      Text('You are offline'),
      Text('$queuedCount requests queued'),
    ],
  ),
)
```

---

## Architecture

```
lib/
 ├── core/
 │    ├── internet_checker.dart     ← Real internet verification (DNS)
 │    ├── network_state.dart        ← Sealed state hierarchy
 │    ├── network_status.dart       ← Connectivity monitor
 │    ├── network_strategy.dart     ← Request strategies
 │    ├── retry_policy.dart         ← Backoff strategies
 │    └── logger.dart               ← Pluggable logger
 ├── manager/
 │    └── network_manager.dart      ← Central orchestrator
 ├── queue/
 │    └── request_queue.dart        ← Offline request queue
 ├── cache/
 │    └── cache_manager.dart        ← TTL cache
 ├── sync/
 │    └── sync_engine.dart          ← Auto-sync on reconnect
 ├── dio/
 │    └── dio_interceptor.dart      ← Dio interceptor
 ├── widgets/
 │    └── network_builder.dart      ← NetworkBuilder & ConnectivityBuilder
 ├── extensions/
 │    ├── bloc_extension.dart       ← Bloc helpers
 │    ├── cubit_extension.dart      ← Standalone Cubit base class
 │    ├── provider_extension.dart   ← ChangeNotifier for Provider
 │    └── riverpod_extension.dart   ← StateNotifier for Riverpod
 └── flutter_network_state.dart     ← Barrel export
```

Every sub-component can be injected individually for testing or customization.

---

## Requirements

| Requirement | Version |
|---|---|
| Dart SDK | `>=3.0.0 <4.0.0` |
| Flutter | `>=3.10.0` |
| Null safety | ✅ |

### Dependencies

| Package | Purpose |
|---|---|
| `connectivity_plus` | Platform connectivity detection |
| `dio` | HTTP client integration |
| `meta` | Annotation utilities |

> **Note:** No dependency on `provider`, `flutter_bloc`, or `riverpod`. All state management integrations are built on plain Dart streams and Flutter SDK primitives.

---

## Comparison

| Feature | `connectivity_plus` | `dio_cache_interceptor` | **`flutter_network_state`** |
|---|:---:|:---:|:---:|
| Online/Offline detection | ✅ | ❌ | ✅ |
| Request strategies | ❌ | Partial | ✅ 4 strategies |
| Cache with TTL | ❌ | ✅ | ✅ + pluggable |
| Offline queue | ❌ | ❌ | ✅ |
| Auto sync on reconnect | ❌ | ❌ | ✅ |
| Retry with backoff | ❌ | ❌ | ✅ 3 strategies |
| Dio interceptor | ❌ | ✅ | ✅ |
| Provider support | ❌ | ❌ | ✅ |
| Cubit support | ❌ | ❌ | ✅ |
| Bloc support | ❌ | ❌ | ✅ |
| Riverpod support | ❌ | ❌ | ✅ |
| Unified state stream | ❌ | ❌ | ✅ |

---

## 💖 Support

If this package helps you build better Flutter apps, consider supporting the development:

<a href="https://sociabuzz.com/faridl29/support">
  <img src="https://img.shields.io/badge/Support_on-SociaBuzz-ff6b6b?style=for-the-badge" alt="Support on SociaBuzz">
</a>

Your support helps keep this package maintained and up-to-date. Every contribution is greatly appreciated! 🙏

---

## License

MIT — see [LICENSE](LICENSE) for details.
