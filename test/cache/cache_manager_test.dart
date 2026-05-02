import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CacheManager cache;

  setUp(() {
    cache = CacheManager(
      defaultTtl: const Duration(minutes: 5),
      logger: NetworkLogger.silent,
    );
  });

  group('CacheManager', () {
    test('set and get returns value', () {
      cache.set('key', 'value');
      expect(cache.get<String>('key'), 'value');
    });

    test('get returns null for missing key', () {
      expect(cache.get<String>('missing'), isNull);
    });

    test('has returns true for existing key', () {
      cache.set('key', 42);
      expect(cache.has('key'), true);
    });

    test('has returns false for missing key', () {
      expect(cache.has('missing'), false);
    });

    test('invalidate removes entry', () {
      cache.set('key', 'val');
      expect(cache.has('key'), true);

      cache.invalidate('key');
      expect(cache.has('key'), false);
      expect(cache.get<String>('key'), isNull);
    });

    test('clear removes all entries', () {
      cache.set('a', 1);
      cache.set('b', 2);
      cache.set('c', 3);

      cache.clear();

      expect(cache.has('a'), false);
      expect(cache.has('b'), false);
      expect(cache.has('c'), false);
    });

    test('expired entry returns null', () {
      // Set with zero TTL — already expired
      cache.set('key', 'val', ttl: Duration.zero);

      // Wait a tiny bit to ensure expiration
      expect(cache.get<String>('key'), isNull);
    });

    test('has evicts expired entry', () {
      cache.set('key', 'val', ttl: Duration.zero);
      expect(cache.has('key'), false);
    });

    test('stores different types', () {
      cache.set('string', 'hello');
      cache.set('int', 42);
      cache.set('list', [1, 2, 3]);
      cache.set('map', {'a': 1});

      expect(cache.get<String>('string'), 'hello');
      expect(cache.get<int>('int'), 42);
      expect(cache.get<List<int>>('list'), [1, 2, 3]);
      expect(cache.get<Map<String, int>>('map'), {'a': 1});
    });

    test('custom TTL overrides default', () {
      // Default is 5 min, use custom 0 duration
      cache.set('key', 'val', ttl: Duration.zero);
      expect(cache.get<String>('key'), isNull);
    });
  });

  group('InMemoryCacheStore', () {
    test('basic CRUD operations', () {
      final store = InMemoryCacheStore();

      store.set('k', 'v');
      expect(store.get('k'), 'v');
      expect(store.containsKey('k'), true);

      store.remove('k');
      expect(store.get('k'), isNull);
      expect(store.containsKey('k'), false);
    });

    test('clear removes everything', () {
      final store = InMemoryCacheStore();
      store.set('a', 1);
      store.set('b', 2);
      store.clear();
      expect(store.containsKey('a'), false);
      expect(store.containsKey('b'), false);
    });
  });

  group('CacheEntry', () {
    test('isExpired returns false when no TTL', () {
      final entry = CacheEntry(
        'value',
        createdAt: DateTime.now(),
        ttl: null,
      );
      expect(entry.isExpired, false);
    });

    test('isExpired returns false when within TTL', () {
      final entry = CacheEntry(
        'value',
        createdAt: DateTime.now(),
        ttl: const Duration(hours: 1),
      );
      expect(entry.isExpired, false);
    });

    test('isExpired returns true when past TTL', () {
      final entry = CacheEntry(
        'value',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ttl: const Duration(hours: 1),
      );
      expect(entry.isExpired, true);
    });
  });
}
