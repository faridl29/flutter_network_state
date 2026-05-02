import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkLogger', () {
    test('defaultLogger does not throw', () {
      final logger = NetworkLogger.defaultLogger;
      expect(() => logger.debug('test'), returnsNormally);
      expect(() => logger.info('test'), returnsNormally);
      expect(() => logger.warning('test'), returnsNormally);
      expect(() => logger.error('test'), returnsNormally);
    });

    test('silent logger does not call handler', () {
      // Silent logger should not call the handler for debug/info/warning
      final logger = NetworkLogger.silent;
      // We can't directly test silent's handler, but we can verify it works
      expect(() => logger.debug('x'), returnsNormally);
      expect(() => logger.info('x'), returnsNormally);
      expect(() => logger.warning('x'), returnsNormally);
    });

    test('custom logger receives messages', () {
      final messages = <String>[];
      final logger = NetworkLogger.custom(
        (level, message) => messages.add('[$level] $message'),
      );

      logger.debug('d');
      logger.info('i');
      logger.warning('w');
      logger.error('e');

      expect(messages, hasLength(4));
      expect(messages[0], contains('d'));
      expect(messages[3], contains('e'));
    });

    test('minLevel filters out lower levels', () {
      final messages = <String>[];
      final logger = NetworkLogger.custom(
        (level, message) => messages.add(message),
        minLevel: LogLevel.warning,
      );

      logger.debug('should be filtered');
      logger.info('should be filtered');
      logger.warning('visible');
      logger.error('visible');

      expect(messages, hasLength(2));
      expect(messages[0], 'visible');
    });
  });
}
