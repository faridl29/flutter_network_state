import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RequestQueue queue;

  setUp(() {
    queue = RequestQueue(logger: NetworkLogger.silent);
  });

  tearDown(() async {
    await queue.dispose();
  });

  group('RequestQueue', () {
    test('starts empty', () {
      expect(queue.isEmpty, true);
      expect(queue.length, 0);
      expect(queue.pending, isEmpty);
    });

    test('enqueue adds request', () {
      queue.enqueue(QueuedRequest(
        id: 'r1',
        execute: () async => 'result',
      ));

      expect(queue.length, 1);
      expect(queue.isEmpty, false);
    });

    test('enqueue multiple requests', () {
      queue.enqueue(QueuedRequest(id: 'r1', execute: () async => 1));
      queue.enqueue(QueuedRequest(id: 'r2', execute: () async => 2));
      queue.enqueue(QueuedRequest(id: 'r3', execute: () async => 3));

      expect(queue.length, 3);
      expect(queue.pending.map((r) => r.id), ['r1', 'r2', 'r3']);
    });

    test('remove removes specific request', () {
      queue.enqueue(QueuedRequest(id: 'r1', execute: () async => 1));
      queue.enqueue(QueuedRequest(id: 'r2', execute: () async => 2));

      final removed = queue.remove('r1');
      expect(removed, true);
      expect(queue.length, 1);
      expect(queue.pending.first.id, 'r2');
    });

    test('remove returns false for non-existent id', () {
      expect(queue.remove('nonexistent'), false);
    });

    test('clear empties the queue', () {
      queue.enqueue(QueuedRequest(id: 'r1', execute: () async => 1));
      queue.enqueue(QueuedRequest(id: 'r2', execute: () async => 2));

      queue.clear();
      expect(queue.isEmpty, true);
    });

    test('processQueue executes all requests', () async {
      var counter = 0;
      queue.enqueue(QueuedRequest(
        id: 'r1',
        execute: () async {
          counter++;
          return 'a';
        },
      ));
      queue.enqueue(QueuedRequest(
        id: 'r2',
        execute: () async {
          counter++;
          return 'b';
        },
      ));

      final results = await queue.processQueue();

      expect(counter, 2);
      expect(results, hasLength(2));
      expect(results[0].isSuccess, true);
      expect(results[0].data, 'a');
      expect(results[1].isSuccess, true);
      expect(results[1].data, 'b');
    });

    test('processQueue handles failures', () async {
      queue.enqueue(QueuedRequest(
        id: 'r1',
        execute: () async => throw Exception('fail'),
        retryPolicy: RetryPolicy.none,
      ));

      final results = await queue.processQueue();

      expect(results, hasLength(1));
      expect(results[0].isSuccess, false);
      expect(results[0].error, isA<Exception>());
    });

    test('processQueue reports progress', () async {
      queue.enqueue(QueuedRequest(id: 'r1', execute: () async => 1));
      queue.enqueue(QueuedRequest(id: 'r2', execute: () async => 2));

      final progressLog = <String>[];
      await queue.processQueue(
        onProgress: (completed, total) {
          progressLog.add('$completed/$total');
        },
      );

      expect(progressLog, ['1/2', '2/2']);
    });

    test('processQueue empties the queue', () async {
      queue.enqueue(QueuedRequest(id: 'r1', execute: () async => 1));

      await queue.processQueue();
      expect(queue.isEmpty, true);
    });

    test('processQueue skips if already processing', () async {
      // Start processing a slow request
      queue.enqueue(QueuedRequest(
        id: 'slow',
        execute: () => Future.delayed(
          const Duration(milliseconds: 100),
          () => 'done',
        ),
        retryPolicy: RetryPolicy.none,
      ));

      // Start first processing (don't await)
      final future1 = queue.processQueue();

      // Try second processing immediately
      final results2 = await queue.processQueue();
      expect(results2, isEmpty); // Should be skipped

      await future1; // Clean up
    });

    test('resultStream emits for each processed request', () async {
      queue.enqueue(QueuedRequest(id: 'r1', execute: () async => 'ok'));

      final streamResults = <QueueProcessResult>[];
      queue.resultStream.listen(streamResults.add);

      await queue.processQueue();

      // Give stream time to emit
      await Future<void>.delayed(Duration.zero);

      expect(streamResults, hasLength(1));
      expect(streamResults[0].isSuccess, true);
    });
  });

  group('InMemoryQueueStore', () {
    test('FIFO ordering', () {
      final store = InMemoryQueueStore();
      store.enqueue(QueuedRequest(id: 'a', execute: () async => null));
      store.enqueue(QueuedRequest(id: 'b', execute: () async => null));
      store.enqueue(QueuedRequest(id: 'c', execute: () async => null));

      expect(store.dequeue()?.id, 'a');
      expect(store.dequeue()?.id, 'b');
      expect(store.dequeue()?.id, 'c');
      expect(store.dequeue(), isNull);
    });

    test('peek does not remove', () {
      final store = InMemoryQueueStore();
      store.enqueue(QueuedRequest(id: 'a', execute: () async => null));

      expect(store.peek()?.id, 'a');
      expect(store.length, 1);
    });

    test('peek returns null when empty', () {
      expect(InMemoryQueueStore().peek(), isNull);
    });
  });

  group('QueuedRequest', () {
    test('enqueuedAt defaults to now', () {
      final before = DateTime.now();
      final request = QueuedRequest(id: 'r', execute: () async => null);
      final after = DateTime.now();

      expect(request.enqueuedAt.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(request.enqueuedAt.isBefore(after.add(const Duration(seconds: 1))), true);
    });

    test('toString includes id and cacheKey', () {
      final request = QueuedRequest(
        id: 'test_id',
        execute: () async => null,
        cacheKey: 'my_key',
      );
      expect(request.toString(), contains('test_id'));
      expect(request.toString(), contains('my_key'));
    });
  });
}
