# Changelog

## 1.0.1

- Upgraded `connectivity_plus` to `^7.0.0` for latest platform support
- Upgraded `meta` to `^1.16.0`
- Bumped minimum Flutter version to `>=3.19.0`
- Added `NetworkNotifier` extension for Provider (ChangeNotifier)
- Added `NetworkCubit` standalone Cubit base class
- Added `NetworkStateNotifier` extension for Riverpod
- Fixed GitHub repository URLs
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

