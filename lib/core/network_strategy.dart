/// Strategies that control how [NetworkManager] resolves a request.
///
/// Each strategy defines the priority between network and cache, allowing
/// fine-grained control over data freshness vs. offline resilience.
library;

import 'package:meta/meta.dart';

/// Base class for network resolution strategies.
///
/// Use one of the concrete subtypes when calling [NetworkManager.request]:
///
/// | Strategy        | Behaviour                                           |
/// |-----------------|-----------------------------------------------------|
/// | [NetworkFirst]  | Try network → fall back to cache on failure.        |
/// | [CacheFirst]    | Try cache → fall back to network on miss/expiry.    |
/// | [CacheOnly]     | Only use cache. Never hits the network.              |
/// | [NetworkOnly]   | Only use network. Never reads/writes cache.          |
@immutable
sealed class NetworkStrategy {
  const NetworkStrategy();
}

/// Try the network first. If it fails (timeout, no connectivity, server error),
/// fall back to cached data when a [cacheKey] is provided.
///
/// This is the default strategy when none is specified.
final class NetworkFirst extends NetworkStrategy {
  const NetworkFirst();

  @override
  String toString() => 'NetworkStrategy.NetworkFirst';
}

/// Check the cache first. If a valid (non-expired) entry exists, return it
/// immediately. Otherwise, execute the network request and cache the result.
final class CacheFirst extends NetworkStrategy {
  const CacheFirst();

  @override
  String toString() => 'NetworkStrategy.CacheFirst';
}

/// Only read from the cache — never touch the network.
///
/// Throws a cache-miss error if no entry is found.
final class CacheOnly extends NetworkStrategy {
  const CacheOnly();

  @override
  String toString() => 'NetworkStrategy.CacheOnly';
}

/// Only use the network — never read or write the cache.
///
/// Useful for mutations or data that must always be fresh.
final class NetworkOnly extends NetworkStrategy {
  const NetworkOnly();

  @override
  String toString() => 'NetworkStrategy.NetworkOnly';
}
