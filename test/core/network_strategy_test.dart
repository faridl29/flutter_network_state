import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkStrategy', () {
    test('NetworkFirst toString', () {
      expect(const NetworkFirst().toString(), 'NetworkStrategy.NetworkFirst');
    });

    test('CacheFirst toString', () {
      expect(const CacheFirst().toString(), 'NetworkStrategy.CacheFirst');
    });

    test('CacheOnly toString', () {
      expect(const CacheOnly().toString(), 'NetworkStrategy.CacheOnly');
    });

    test('NetworkOnly toString', () {
      expect(const NetworkOnly().toString(), 'NetworkStrategy.NetworkOnly');
    });

    test('Strategies are sealed — pattern matching is exhaustive', () {
      const NetworkStrategy strategy = CacheFirst();

      final result = switch (strategy) {
        NetworkFirst() => 'network_first',
        CacheFirst() => 'cache_first',
        CacheOnly() => 'cache_only',
        NetworkOnly() => 'network_only',
      };

      expect(result, 'cache_first');
    });
  });
}
