# sqflite Queue Store

Copy this implementation into your project to use SQLite as the persistent
queue backend.

## Dependencies

```yaml
dependencies:
  sqflite: ^2.3.0
  path: ^1.8.0
```

## Implementation

```dart
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_network_state/flutter_network_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// A [QueueStore] backed by sqflite for persistent offline request storage.
class SqfliteQueueStore implements QueueStore {
  SqfliteQueueStore._({
    required Database db,
    required RequestExecutor executor,
  })  : _db = db,
        _executor = executor;

  /// Opens (or creates) the SQLite database and returns a ready-to-use store.
  static Future<SqfliteQueueStore> open({
    required RequestExecutor executor,
    String dbName = 'network_queue.db',
  }) async {
    final dbPath = p.join(await getDatabasesPath(), dbName);
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS queue (
            id TEXT PRIMARY KEY,
            method TEXT NOT NULL,
            url TEXT NOT NULL,
            headers TEXT,
            body TEXT,
            cache_key TEXT,
            max_retries INTEGER DEFAULT 3,
            enqueued_at TEXT NOT NULL
          )
        ''');
      },
    );

    final store = SqfliteQueueStore._(db: db, executor: executor);
    await store._loadFromDb();
    return store;
  }

  final Database _db;
  final RequestExecutor _executor;
  final Queue<SerializableRequest> _queue = Queue<SerializableRequest>();

  static const _table = 'queue';

  Future<void> _loadFromDb() async {
    _queue.clear();
    final rows = await _db.query(_table, orderBy: 'enqueued_at ASC');
    for (final row in rows) {
      _queue.add(SerializableRequest(
        id: row['id'] as String,
        method: row['method'] as String,
        url: row['url'] as String,
        headers: row['headers'] != null
            ? Map<String, String>.from(
                jsonDecode(row['headers'] as String) as Map,
              )
            : const {},
        body: row['body'] as String?,
        cacheKey: row['cache_key'] as String?,
        maxRetries: (row['max_retries'] as int?) ?? 3,
        enqueuedAt: DateTime.parse(row['enqueued_at'] as String),
      ));
    }
  }

  Future<void> _insert(SerializableRequest sr) async {
    await _db.insert(
      _table,
      {
        'id': sr.id,
        'method': sr.method,
        'url': sr.url,
        'headers': jsonEncode(sr.headers),
        'body': sr.body,
        'cache_key': sr.cacheKey,
        'max_retries': sr.maxRetries,
        'enqueued_at':
            (sr.enqueuedAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _deleteById(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// Enqueue a [SerializableRequest] with full persistence.
  Future<void> enqueueSerializable(SerializableRequest request) async {
    _queue.add(request);
    await _insert(request);
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
    _insert(sr); // fire-and-forget
  }

  @override
  QueuedRequest? dequeue() {
    if (_queue.isEmpty) return null;
    final sr = _queue.removeFirst();
    _deleteById(sr.id); // fire-and-forget
    return _toQueuedRequest(sr);
  }

  @override
  QueuedRequest? peek() {
    if (_queue.isEmpty) return null;
    return _toQueuedRequest(_queue.first);
  }

  @override
  bool remove(String id) {
    final before = _queue.length;
    _queue.removeWhere((r) => r.id == id);
    if (_queue.length < before) {
      _deleteById(id); // fire-and-forget
      return true;
    }
    return false;
  }

  @override
  List<QueuedRequest> get all =>
      _queue.map(_toQueuedRequest).toList(growable: false);

  @override
  int get length => _queue.length;

  @override
  bool get isEmpty => _queue.isEmpty;

  @override
  void clear() {
    _queue.clear();
    _db.delete(_table); // fire-and-forget
  }

  /// Close the database connection.
  Future<void> close() async {
    await _db.close();
  }

  QueuedRequest _toQueuedRequest(SerializableRequest sr) {
    return QueuedRequest(
      id: sr.id,
      execute: () => _executor(sr),
      cacheKey: sr.cacheKey,
      retryPolicy: RetryPolicy(maxRetries: sr.maxRetries),
      enqueuedAt: sr.enqueuedAt,
    );
  }
}
```

## Usage

```dart
final store = await SqfliteQueueStore.open(
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

// Don't forget to close when done
await store.close();
```
