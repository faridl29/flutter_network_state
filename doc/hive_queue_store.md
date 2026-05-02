# Hive Queue Store

Copy this implementation into your project to use Hive as the persistent
queue backend.

## Dependencies

```yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0
```

## Implementation

```dart
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:hive/hive.dart';

/// A [QueueStore] backed by Hive for persistent offline request storage.
class HiveQueueStore implements QueueStore {
  HiveQueueStore({
    required Box<String> box,
    required RequestExecutor executor,
  })  : _box = box,
        _executor = executor {
    _loadFromBox();
  }

  final Box<String> _box;
  final RequestExecutor _executor;
  final Queue<SerializableRequest> _queue = Queue<SerializableRequest>();

  void _loadFromBox() {
    _queue.clear();
    for (final key in _box.keys) {
      try {
        final json = jsonDecode(_box.get(key)!) as Map<String, dynamic>;
        _queue.add(SerializableRequest.fromJson(json));
      } catch (_) {
        // Skip corrupted entries
      }
    }
  }

  /// Enqueue a [SerializableRequest] with full persistence.
  void enqueueSerializable(SerializableRequest request) {
    _queue.add(request);
    _box.put(request.id, jsonEncode(request.toJson()));
  }

  @override
  void enqueue(QueuedRequest request) {
    final sr = SerializableRequest(
      id: request.id,
      method: 'GET',
      url: '',
      cacheKey: request.cacheKey,
      maxRetries: request.retryPolicy.maxRetries,
      enqueuedAt: request.enqueuedAt,
    );
    _queue.add(sr);
    _box.put(sr.id, jsonEncode(sr.toJson()));
  }

  @override
  QueuedRequest? dequeue() {
    if (_queue.isEmpty) return null;
    final sr = _queue.removeFirst();
    _box.delete(sr.id);
    return QueuedRequest(
      id: sr.id,
      execute: () => _executor(sr),
      cacheKey: sr.cacheKey,
      retryPolicy: RetryPolicy(maxRetries: sr.maxRetries),
      enqueuedAt: sr.enqueuedAt,
    );
  }

  @override
  QueuedRequest? peek() {
    if (_queue.isEmpty) return null;
    final sr = _queue.first;
    return QueuedRequest(
      id: sr.id,
      execute: () => _executor(sr),
      cacheKey: sr.cacheKey,
      retryPolicy: RetryPolicy(maxRetries: sr.maxRetries),
      enqueuedAt: sr.enqueuedAt,
    );
  }

  @override
  bool remove(String id) {
    final before = _queue.length;
    _queue.removeWhere((r) => r.id == id);
    if (_queue.length < before) {
      _box.delete(id);
      return true;
    }
    return false;
  }

  @override
  List<QueuedRequest> get all => _queue
      .map((sr) => QueuedRequest(
            id: sr.id,
            execute: () => _executor(sr),
            cacheKey: sr.cacheKey,
            retryPolicy: RetryPolicy(maxRetries: sr.maxRetries),
            enqueuedAt: sr.enqueuedAt,
          ))
      .toList(growable: false);

  @override
  int get length => _queue.length;

  @override
  bool get isEmpty => _queue.isEmpty;

  @override
  void clear() {
    _queue.clear();
    _box.clear();
  }
}
```

## Usage

```dart
import 'package:hive_flutter/hive_flutter.dart';

await Hive.initFlutter();
final box = await Hive.openBox<String>('network_queue');

final store = HiveQueueStore(
  box: box,
  executor: (req) async {
    final response = await dio.request(
      req.url,
      options: Options(method: req.method, headers: req.headers),
      data: req.body,
    );
    return response.data;
  },
);

final manager = NetworkManager(queue: RequestQueue(store: store));
```
