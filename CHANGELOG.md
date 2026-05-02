# Changelog

## 1.1.0

### 🚀 Feature Release

**Persistent Queue**
- Added `PersistentQueueStore` — JSON file-based queue that survives app restarts
- Added `SerializableRequest` model for disk-safe HTTP request metadata
- Added `RequestExecutor` callback for replaying persisted requests
- Added `HiveQueueStore` reference implementation (`doc/hive_queue_store.md`)
- Added `SqfliteQueueStore` reference implementation (`doc/sqflite_queue_store.md`)

**Real Internet Verification**
- Added `InternetChecker` — DNS lookup-based connectivity verification
- Detects captive portals, DNS failures, and firewalled connections
- Periodic monitoring with deduped status stream

**Reactive Widgets**
- Added `NetworkBuilder` — rebuilds UI based on `NetworkState` stream
- Added `ConnectivityBuilder` — shows online/offline UI branches

**State Management**
- Added `NetworkNotifier` extension for Provider (ChangeNotifier)
- Added `NetworkCubit` standalone Cubit base class
- Added `NetworkStateNotifier` extension for Riverpod

**Testing**
- Added 80+ unit tests covering core, cache, queue, persistent queue, and retry

**Dependencies**
- Upgraded `connectivity_plus` to `^7.0.0`
- Upgraded `meta` to `^1.16.0`
- Bumped minimum Flutter version to `>=3.19.0`

**Fixes**
- Fixed GitHub repository URLs for pub.dev
- Shortened package description for pub.dev compliance

## 1.0.0

### 🎉 Initial Release

**Core**
- Sealed `NetworkState` hierarchy: `Idle`, `Loading`, `Offline`, `Syncing`, `Success<T>`, `Error`
- Sealed `NetworkStrategy`: `NetworkFirst`, `CacheFirst`, `CacheOnly`, `NetworkOnly`
- Stream-based `NetworkStatusMonitor` wrapping `connectivity_plus`
- Pluggable `NetworkLogger` with severity levels (debug, info, warning, error)

**Request Orchestration**
- `NetworkManager.request<T>()` API with strategy-based resolution
- Automatic cache fallback on network failure (NetworkFirst / CacheFirst)
- Offline request queueing with per-request retry policies

**Cache**
- In-memory `CacheManager` with TTL support
- Pluggable `CacheStore` interface for custom persistence (Hive, Isar, etc.)

**Queue & Sync**
- FIFO `RequestQueue` with pluggable `QueueStore`
- `SyncEngine` — automatically drains queue on connectivity restore
- Progress tracking via `Syncing` state (`completedRequests / totalRequests`)

**Retry**
- `RetryPolicy` with configurable max retries
- `ExponentialBackoff` with ±25% jitter
- `LinearBackoff` and `ConstantBackoff` alternatives
- Custom `shouldRetry` predicate support

**Dio Integration**
- `NetworkDioInterceptor` — drop-in interceptor for any `Dio` instance
- Auto-retry on transient failures (timeouts, 500, 502, 503, 429)
- Automatic offline queueing and replay
- Configurable request/response/error logging

**State Management**
- `NetworkNotifier` — `ChangeNotifier` wrapper for Provider
- `NetworkCubit` — standalone Cubit base class (no `flutter_bloc` dependency)
- `executeAndEmit()` / `bindToEmit()` — extensions for `flutter_bloc` Cubit/Bloc
- `NetworkStateNotifier` — Riverpod-compatible notifier with `execute()` helper
- `createNotifier()` — extension on `NetworkManager` for Riverpod providers
- `asNetworkStates()` — transform any `Stream<T>` into `Stream<NetworkState>`
- Zero external state management dependencies — all built on Flutter SDK primitives

