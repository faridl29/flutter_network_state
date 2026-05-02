import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkState', () {
    test('Idle equality', () {
      expect(const Idle(), equals(const Idle()));
      expect(const Idle().hashCode, equals(const Idle().hashCode));
    });

    test('Idle toString', () {
      expect(const Idle().toString(), 'NetworkState.Idle');
    });

    test('Loading equality with same message', () {
      expect(
        const Loading(message: 'test'),
        equals(const Loading(message: 'test')),
      );
    });

    test('Loading equality with different message', () {
      expect(
        const Loading(message: 'a'),
        isNot(equals(const Loading(message: 'b'))),
      );
    });

    test('Loading without message', () {
      expect(const Loading().message, isNull);
    });

    test('Offline tracks queued requests', () {
      const state = Offline(queuedRequests: 5);
      expect(state.queuedRequests, 5);
    });

    test('Offline default queued requests is 0', () {
      const state = Offline();
      expect(state.queuedRequests, 0);
    });

    test('Syncing progress calculation', () {
      const state = Syncing(totalRequests: 10, completedRequests: 3);
      expect(state.progress, 0.3);
    });

    test('Syncing progress is 0 when total is 0', () {
      const state = Syncing(totalRequests: 0, completedRequests: 0);
      expect(state.progress, 0);
    });

    test('Syncing equality', () {
      expect(
        const Syncing(totalRequests: 5, completedRequests: 2),
        equals(const Syncing(totalRequests: 5, completedRequests: 2)),
      );
      expect(
        const Syncing(totalRequests: 5, completedRequests: 2),
        isNot(equals(const Syncing(totalRequests: 5, completedRequests: 3))),
      );
    });

    test('Success holds data', () {
      const state = Success<String>('hello');
      expect(state.data, 'hello');
      expect(state.fromCache, false);
    });

    test('Success fromCache flag', () {
      const state = Success<int>(42, fromCache: true);
      expect(state.data, 42);
      expect(state.fromCache, true);
    });

    test('Success equality', () {
      expect(
        const Success<String>('a'),
        equals(const Success<String>('a')),
      );
      expect(
        const Success<String>('a', fromCache: true),
        isNot(equals(const Success<String>('a', fromCache: false))),
      );
    });

    test('Error holds message and metadata', () {
      const state = Error('fail', isRetryable: false);
      expect(state.message, 'fail');
      expect(state.isRetryable, false);
      expect(state.exception, isNull);
    });

    test('Error equality', () {
      expect(
        const Error('x'),
        equals(const Error('x')),
      );
      expect(
        const Error('x', isRetryable: true),
        isNot(equals(const Error('x', isRetryable: false))),
      );
    });

    test('All states are NetworkState subtypes', () {
      final states = <NetworkState>[
        const Idle(),
        const Loading(),
        const Offline(),
        const Syncing(),
        const Success<String>('data'),
        const Error('err'),
      ];
      expect(states, hasLength(6));
      for (final s in states) {
        expect(s, isA<NetworkState>());
      }
    });

    test('Pattern matching covers all cases', () {
      const NetworkState state = Success<int>(42);

      final result = switch (state) {
        Idle() => 'idle',
        Loading() => 'loading',
        Offline() => 'offline',
        Syncing() => 'syncing',
        Success<int>() => 'success:${state.data}',
        Success() => 'success:other',
        Error() => 'error',
      };

      expect(result, 'success:42');
    });
  });
}
