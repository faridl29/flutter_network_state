import 'dart:convert';
import 'dart:io';

import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late PersistentQueueStore store;
  late List<SerializableRequest> executedRequests;

  Future<dynamic> mockExecutor(SerializableRequest req) async {
    executedRequests.add(req);
    return {'status': 'ok', 'id': req.id};
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('persistent_queue_test_');
    executedRequests = [];
    store = PersistentQueueStore(
      directory: tempDir,
      executor: mockExecutor,
      logger: NetworkLogger.silent,
    );
    await store.initialize();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SerializableRequest', () {
    test('toJson and fromJson roundtrip', () {
      final original = SerializableRequest(
        id: 'req_1',
        method: 'POST',
        url: 'https://api.example.com/users',
        headers: const {'Authorization': 'Bearer token123'},
        body: '{"name": "John"}',
        cacheKey: 'user_1',
        maxRetries: 5,
        enqueuedAt: DateTime(2026, 1, 1, 12, 0),
      );

      final json = original.toJson();
      final restored = SerializableRequest.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.method, original.method);
      expect(restored.url, original.url);
      expect(restored.headers, original.headers);
      expect(restored.body, original.body);
      expect(restored.cacheKey, original.cacheKey);
      expect(restored.maxRetries, original.maxRetries);
      expect(restored.enqueuedAt, original.enqueuedAt);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'r1',
        'method': 'GET',
        'url': 'https://example.com',
      };

      final request = SerializableRequest.fromJson(json);
      expect(request.headers, isEmpty);
      expect(request.body, isNull);
      expect(request.cacheKey, isNull);
      expect(request.maxRetries, 3);
    });

    test('toString includes key fields', () {
      const request = SerializableRequest(
        id: 'test',
        method: 'GET',
        url: 'https://example.com',
      );
      expect(request.toString(), contains('test'));
      expect(request.toString(), contains('GET'));
    });
  });

  group('PersistentQueueStore', () {
    test('starts empty after init with no file', () {
      expect(store.isEmpty, true);
      expect(store.length, 0);
    });

    test('enqueueSerializable adds and persists', () async {
      await store.enqueueSerializable(const SerializableRequest(
        id: 'r1',
        method: 'POST',
        url: 'https://api.example.com/data',
        body: '{"key":"value"}',
      ));

      expect(store.length, 1);

      // Verify file was written
      final file = File('${tempDir.path}/network_queue.json');
      expect(await file.exists(), true);

      final content = jsonDecode(await file.readAsString()) as List;
      expect(content, hasLength(1));
      expect(content[0]['id'], 'r1');
    });

    test('dequeue returns and removes first item', () async {
      await store.enqueueSerializable(const SerializableRequest(
        id: 'r1',
        method: 'GET',
        url: 'https://a.com',
      ));
      await store.enqueueSerializable(const SerializableRequest(
        id: 'r2',
        method: 'GET',
        url: 'https://b.com',
      ));

      final request = store.dequeue();
      expect(request?.id, 'r1');
      expect(store.length, 1);
    });

    test('dequeue returns null when empty', () {
      expect(store.dequeue(), isNull);
    });

    test('peek does not remove', () async {
      await store.enqueueSerializable(const SerializableRequest(
        id: 'r1',
        method: 'GET',
        url: 'https://a.com',
      ));

      final peeked = store.peek();
      expect(peeked?.id, 'r1');
      expect(store.length, 1);
    });

    test('remove removes specific request', () async {
      await store.enqueueSerializable(const SerializableRequest(
        id: 'r1',
        method: 'GET',
        url: 'https://a.com',
      ));
      await store.enqueueSerializable(const SerializableRequest(
        id: 'r2',
        method: 'GET',
        url: 'https://b.com',
      ));

      expect(store.remove('r1'), true);
      expect(store.length, 1);
      expect(store.all.first.id, 'r2');
    });

    test('remove returns false for non-existent id', () {
      expect(store.remove('nonexistent'), false);
    });

    test('clear removes all and persists', () async {
      await store.enqueueSerializable(const SerializableRequest(
        id: 'r1',
        method: 'GET',
        url: 'https://a.com',
      ));

      store.clear();
      expect(store.isEmpty, true);

      // File should have empty array
      final file = File('${tempDir.path}/network_queue.json');
      final content = jsonDecode(await file.readAsString()) as List;
      expect(content, isEmpty);
    });

    test('persists and restores across instances', () async {
      // Enqueue in first instance
      await store.enqueueSerializable(const SerializableRequest(
        id: 'persist_1',
        method: 'PUT',
        url: 'https://api.example.com/update',
        headers: {'Content-Type': 'application/json'},
        body: '{"updated": true}',
        cacheKey: 'update_cache',
        maxRetries: 5,
      ));
      await store.enqueueSerializable(const SerializableRequest(
        id: 'persist_2',
        method: 'DELETE',
        url: 'https://api.example.com/item/42',
      ));

      // Create new instance from same directory
      final store2 = PersistentQueueStore(
        directory: tempDir,
        executor: mockExecutor,
        logger: NetworkLogger.silent,
      );
      await store2.initialize();

      expect(store2.length, 2);
      expect(store2.requests[0].id, 'persist_1');
      expect(store2.requests[0].method, 'PUT');
      expect(store2.requests[0].headers['Content-Type'], 'application/json');
      expect(store2.requests[0].body, '{"updated": true}');
      expect(store2.requests[0].cacheKey, 'update_cache');
      expect(store2.requests[0].maxRetries, 5);
      expect(store2.requests[1].id, 'persist_2');
      expect(store2.requests[1].method, 'DELETE');
    });

    test('dequeued request uses executor callback', () async {
      await store.enqueueSerializable(const SerializableRequest(
        id: 'exec_test',
        method: 'POST',
        url: 'https://api.example.com/action',
        body: '{"action": "test"}',
      ));

      final queuedRequest = store.dequeue()!;
      final result = await queuedRequest.execute();

      expect(executedRequests, hasLength(1));
      expect(executedRequests[0].id, 'exec_test');
      expect(executedRequests[0].method, 'POST');
      expect(executedRequests[0].body, '{"action": "test"}');
      expect(result['status'], 'ok');
    });

    test('works with RequestQueue.processQueue', () async {
      await store.enqueueSerializable(const SerializableRequest(
        id: 'q1',
        method: 'GET',
        url: 'https://api.example.com/data1',
      ));
      await store.enqueueSerializable(const SerializableRequest(
        id: 'q2',
        method: 'GET',
        url: 'https://api.example.com/data2',
      ));

      final queue = RequestQueue(store: store, logger: NetworkLogger.silent);
      final results = await queue.processQueue();

      expect(results, hasLength(2));
      expect(results[0].isSuccess, true);
      expect(results[1].isSuccess, true);
      expect(executedRequests, hasLength(2));

      await queue.dispose();
    });

    test('handles corrupted file gracefully', () async {
      // Write garbage to the file
      final file = File('${tempDir.path}/network_queue.json');
      await file.writeAsString('not valid json!!!');

      // New instance should handle gracefully
      final store2 = PersistentQueueStore(
        directory: tempDir,
        executor: mockExecutor,
        logger: NetworkLogger.silent,
      );
      await store2.initialize();

      expect(store2.isEmpty, true); // Should be empty, not crash
    });

    test('FIFO order is maintained', () async {
      for (var i = 1; i <= 5; i++) {
        await store.enqueueSerializable(SerializableRequest(
          id: 'r$i',
          method: 'GET',
          url: 'https://example.com/$i',
        ));
      }

      final ids = <String>[];
      while (!store.isEmpty) {
        ids.add(store.dequeue()!.id);
      }

      expect(ids, ['r1', 'r2', 'r3', 'r4', 'r5']);
    });
  });
}
