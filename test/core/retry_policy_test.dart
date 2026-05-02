import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetryPolicy', () {
    test('default policy has 3 retries', () {
      expect(RetryPolicy.defaultPolicy.maxRetries, 3);
    });

    test('none policy has 0 retries', () {
      expect(RetryPolicy.none.maxRetries, 0);
      expect(RetryPolicy.none.canRetry(0), false);
    });

    test('canRetry checks attempt against maxRetries', () {
      const policy = RetryPolicy(maxRetries: 2);
      expect(policy.canRetry(0), true);
      expect(policy.canRetry(1), true);
      expect(policy.canRetry(2), false);
      expect(policy.canRetry(3), false);
    });
  });

  group('ExponentialBackoff', () {
    test('delay increases exponentially', () {
      const backoff = ExponentialBackoff(
        baseDelay: Duration(seconds: 1),
        withJitter: false,
      );

      expect(backoff.delay(0), const Duration(seconds: 1));
      expect(backoff.delay(1), const Duration(seconds: 2));
      expect(backoff.delay(2), const Duration(seconds: 4));
    });

    test('delay is capped at maxDelay', () {
      const backoff = ExponentialBackoff(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
        withJitter: false,
      );

      expect(backoff.delay(10).inSeconds, 5);
    });

    test('jitter keeps delay within ±25% range', () {
      const backoff = ExponentialBackoff(
        baseDelay: Duration(seconds: 4),
        withJitter: true,
      );

      // Run multiple times to test randomness
      for (var i = 0; i < 20; i++) {
        final delay = backoff.delay(0);
        // 4s ±25% = 3s to 5s
        expect(delay.inMilliseconds, greaterThanOrEqualTo(3000));
        expect(delay.inMilliseconds, lessThanOrEqualTo(5000));
      }
    });
  });

  group('ConstantBackoff', () {
    test('always returns same delay', () {
      const backoff = ConstantBackoff(duration: Duration(seconds: 3));

      expect(backoff.delay(0), const Duration(seconds: 3));
      expect(backoff.delay(1), const Duration(seconds: 3));
      expect(backoff.delay(5), const Duration(seconds: 3));
    });
  });

  group('LinearBackoff', () {
    test('delay increases linearly', () {
      const backoff = LinearBackoff(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
      );

      expect(backoff.delay(0), const Duration(seconds: 1));
      expect(backoff.delay(1), const Duration(seconds: 2));
      expect(backoff.delay(2), const Duration(seconds: 3));
    });

    test('delay is capped at maxDelay', () {
      const backoff = LinearBackoff(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 3),
      );

      expect(backoff.delay(10), const Duration(seconds: 3));
    });
  });
}
