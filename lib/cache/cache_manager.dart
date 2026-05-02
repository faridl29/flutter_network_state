/// In-memory cache with TTL (time-to-live) support.
///
/// This is intentionally kept simple and in-memory. For persistent storage,
/// implement [CacheStore] and inject it into [CacheManager].
library;

import 'package:flutter_network_state/core/logger.dart';

// ---------------------------------------------------------------------------
// Cache store abstraction
// ---------------------------------------------------------------------------

/// Abstraction over the underlying storage mechanism.
///
/// The default implementation is [InMemoryCacheStore]. Users can provide their
/// own (e.g. `SharedPreferences`, `Hive`, `Isar`) for persistence.
abstract class CacheStore {
  /// Retrieve a cached value by [key], or `null` if absent.
  dynamic get(String key);

  /// Store a [value] under [key].
  void set(String key, dynamic value);

  /// Remove a single entry.
  void remove(String key);

  /// Remove all entries.
  void clear();

  /// Whether the store contains [key].
  bool containsKey(String key);
}

/// Simple in-memory implementation of [CacheStore].
class InMemoryCacheStore implements CacheStore {
  final Map<String, dynamic> _data = {};

  @override
  dynamic get(String key) => _data[key];

  @override
  void set(String key, dynamic value) => _data[key] = value;

  @override
  void remove(String key) => _data.remove(key);

  @override
  void clear() => _data.clear();

  @override
  bool containsKey(String key) => _data.containsKey(key);
}

// ---------------------------------------------------------------------------
// Cache entry
// ---------------------------------------------------------------------------

/// Wrapper around a cached value that tracks creation time for TTL checks.
class CacheEntry<T> {
  CacheEntry(this.value, {required this.createdAt, this.ttl});

  /// The cached value.
  final T value;

  /// When this entry was written.
  final DateTime createdAt;

  /// Optional time-to-live. If `null`, the entry never expires.
  final Duration? ttl;

  /// Whether this entry has expired based on its [ttl].
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(createdAt) > ttl!;
  }
}

// ---------------------------------------------------------------------------
// Cache manager
// ---------------------------------------------------------------------------

/// Manages cached data with TTL support.
///
/// ```dart
/// final cache = CacheManager();
/// cache.set('user', userData, ttl: Duration(minutes: 5));
///
/// final user = cache.get<UserModel>('user');
/// ```
class CacheManager {
  /// Creates a [CacheManager].
  ///
  /// * [store] — the backing store (defaults to [InMemoryCacheStore]).
  /// * [defaultTtl] — the default TTL applied when none is specified per-call.
  /// * [logger] — optional logger.
  CacheManager({
    CacheStore? store,
    this.defaultTtl = const Duration(minutes: 5),
    NetworkLogger? logger,
  })  : _store = store ?? InMemoryCacheStore(),
        _logger = logger ?? NetworkLogger.defaultLogger;

  final CacheStore _store;
  final NetworkLogger _logger;

  /// Default time-to-live for entries that don't specify their own.
  final Duration defaultTtl;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Retrieve a cached value of type [T] by [key].
  ///
  /// Returns `null` if the key doesn't exist or the entry has expired.
  /// Expired entries are automatically evicted.
  T? get<T>(String key) {
    final raw = _store.get(key);
    if (raw == null) return null;

    if (raw is CacheEntry) {
      if (raw.isExpired) {
        _logger.debug('CacheManager: entry "$key" expired — evicting');
        _store.remove(key);
        return null;
      }
      return raw.value as T;
    }

    // Stored without CacheEntry wrapper (shouldn't happen, but be safe).
    return raw as T;
  }

  /// Store a [value] under [key] with an optional [ttl].
  ///
  /// If [ttl] is not provided, [defaultTtl] is used.
  void set<T>(String key, T value, {Duration? ttl}) {
    final entry = CacheEntry<T>(
      value,
      createdAt: DateTime.now(),
      ttl: ttl ?? defaultTtl,
    );
    _store.set(key, entry);
    _logger.debug(
      'CacheManager: cached "$key" (ttl: ${entry.ttl?.inSeconds}s)',
    );
  }

  /// Check whether a valid (non-expired) entry exists for [key].
  bool has(String key) {
    final raw = _store.get(key);
    if (raw == null) return false;
    if (raw is CacheEntry && raw.isExpired) {
      _store.remove(key);
      return false;
    }
    return true;
  }

  /// Remove a single cache entry.
  void invalidate(String key) {
    _store.remove(key);
    _logger.debug('CacheManager: invalidated "$key"');
  }

  /// Remove all entries.
  void clear() {
    _store.clear();
    _logger.info('CacheManager: cleared all entries');
  }
}
