/// Persistent queue store that survives app restarts.
///
/// Stores serializable request metadata as JSON on disk. Unlike closures,
/// this approach persists HTTP request details (method, URL, headers, body)
/// so they can be reconstructed and replayed after an app restart.
///
/// ```dart
/// final store = PersistentQueueStore(
///   directory: await getApplicationDocumentsDirectory(),
/// );
/// await store.initialize();
///
/// final queue = RequestQueue(store: store);
/// ```
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_network_state/core/logger.dart';
import 'package:flutter_network_state/core/retry_policy.dart';
import 'package:flutter_network_state/queue/request_queue.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Serializable request model
// ---------------------------------------------------------------------------

/// A serializable representation of an HTTP request that can be persisted
/// to disk and reconstructed later.
///
/// Unlike [QueuedRequest] which holds a closure, [SerializableRequest]
/// stores the raw HTTP details so the request can be replayed from storage.
///
/// ```dart
/// final request = SerializableRequest(
///   id: 'update_profile_123',
///   method: 'POST',
///   url: 'https://api.example.com/profile',
///   headers: {'Authorization': 'Bearer token'},
///   body: '{"name": "John"}',
///   cacheKey: 'profile',
///   maxRetries: 3,
/// );
/// ```
@immutable
class SerializableRequest {
  const SerializableRequest({
    required this.id,
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.cacheKey,
    this.maxRetries = 3,
    this.enqueuedAt,
  });

  /// Deserialize from JSON map.
  factory SerializableRequest.fromJson(Map<String, dynamic> json) {
    return SerializableRequest(
      id: json['id'] as String,
      method: json['method'] as String,
      url: json['url'] as String,
      headers: Map<String, String>.from(
        (json['headers'] as Map<String, dynamic>?) ?? {},
      ),
      body: json['body'] as String?,
      cacheKey: json['cacheKey'] as String?,
      maxRetries: (json['maxRetries'] as int?) ?? 3,
      enqueuedAt: json['enqueuedAt'] != null
          ? DateTime.parse(json['enqueuedAt'] as String)
          : null,
    );
  }

  /// Unique identifier.
  final String id;

  /// HTTP method (GET, POST, PUT, DELETE, PATCH).
  final String method;

  /// Full URL including query parameters.
  final String url;

  /// HTTP headers.
  final Map<String, String> headers;

  /// Request body (JSON string for POST/PUT/PATCH).
  final String? body;

  /// Optional cache key for the result.
  final String? cacheKey;

  /// Maximum number of retries.
  final int maxRetries;

  /// When this request was enqueued.
  final DateTime? enqueuedAt;

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'url': url,
        'headers': headers,
        'body': body,
        'cacheKey': cacheKey,
        'maxRetries': maxRetries,
        'enqueuedAt': (enqueuedAt ?? DateTime.now()).toIso8601String(),
      };

  @override
  String toString() =>
      'SerializableRequest(id: $id, $method $url, cacheKey: $cacheKey)';
}

// ---------------------------------------------------------------------------
// Request executor
// ---------------------------------------------------------------------------

/// Callback that executes a [SerializableRequest] and returns the result.
///
/// Users must provide this when creating a [PersistentQueueStore] so the
/// store knows how to replay persisted requests.
///
/// Example with Dio:
/// ```dart
/// Future<dynamic> executor(SerializableRequest req) async {
///   final response = await dio.request(
///     req.url,
///     options: Options(method: req.method, headers: req.headers),
///     data: req.body,
///   );
///   return response.data;
/// }
/// ```
typedef RequestExecutor = Future<dynamic> Function(SerializableRequest request);

// ---------------------------------------------------------------------------
// Persistent queue store
// ---------------------------------------------------------------------------

/// A [QueueStore] implementation that persists queued requests as a JSON
/// file on disk.
///
/// **How it works:**
/// 1. Requests are stored in-memory as a [Queue] for fast access
/// 2. Every mutation (enqueue, dequeue, remove, clear) writes the full
///    queue to a JSON file
/// 3. On [initialize], the file is read and the queue is restored
///
/// **Important:** Because closures cannot be serialized, this store works
/// with [SerializableRequest] instead of [QueuedRequest]. Use [toQueuedRequest]
/// to convert when processing.
///
/// ```dart
/// final store = PersistentQueueStore(
///   directory: appDocDir,
///   executor: (req) async {
///     return await dio.request(req.url, options: Options(method: req.method));
///   },
/// );
/// await store.initialize();
/// ```
class PersistentQueueStore implements QueueStore {
  PersistentQueueStore({
    required Directory directory,
    required RequestExecutor executor,
    String fileName = 'network_queue.json',
    NetworkLogger? logger,
  })  : _file = File('${directory.path}/$fileName'),
        _executor = executor,
        _logger = logger ?? NetworkLogger.defaultLogger;

  final File _file;
  final RequestExecutor _executor;
  final NetworkLogger _logger;
  final Queue<SerializableRequest> _queue = Queue<SerializableRequest>();

  /// Whether [initialize] has been called.
  bool _initialized = false;

  /// The underlying serializable requests (read-only snapshot).
  List<SerializableRequest> get requests => List.unmodifiable(_queue);

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Load persisted requests from disk. Must be called before using the store.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (await _file.exists()) {
        final content = await _file.readAsString();
        if (content.isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          for (final item in list) {
            _queue.add(
              SerializableRequest.fromJson(item as Map<String, dynamic>),
            );
          }
          _logger.info(
            'PersistentQueueStore: restored ${_queue.length} request(s) '
            'from disk',
          );
        }
      }
    } catch (e) {
      _logger.error('PersistentQueueStore: failed to load from disk — $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Enqueue serializable requests
  // ---------------------------------------------------------------------------

  /// Enqueue a [SerializableRequest] (preferred for persistent storage).
  Future<void> enqueueSerializable(SerializableRequest request) async {
    _queue.add(request);
    await _persist();
    _logger.debug('PersistentQueueStore: enqueued "${request.id}"');
  }

  // ---------------------------------------------------------------------------
  // QueueStore interface
  // ---------------------------------------------------------------------------

  @override
  void enqueue(QueuedRequest request) {
    // Convert QueuedRequest → SerializableRequest if possible.
    // Note: the execute closure will be lost. For persistent storage,
    // prefer enqueueSerializable().
    _queue.add(SerializableRequest(
      id: request.id,
      method: 'GET',
      url: '',
      cacheKey: request.cacheKey,
      maxRetries: request.retryPolicy.maxRetries,
      enqueuedAt: request.enqueuedAt,
    ));
    _persistSync();
    _logger.warning(
      'PersistentQueueStore: enqueued "${request.id}" via QueueStore '
      'interface — execute closure will NOT be persisted. '
      'Use enqueueSerializable() for full persistence.',
    );
  }

  @override
  QueuedRequest? dequeue() {
    if (_queue.isEmpty) return null;
    final serializable = _queue.removeFirst();
    _persistSync();
    return _toQueuedRequest(serializable);
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
      _persistSync();
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
    _persistSync();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  QueuedRequest _toQueuedRequest(SerializableRequest sr) {
    return QueuedRequest(
      id: sr.id,
      execute: () => _executor(sr),
      cacheKey: sr.cacheKey,
      retryPolicy: RetryPolicy(maxRetries: sr.maxRetries),
      enqueuedAt: sr.enqueuedAt,
    );
  }

  Future<void> _persist() async {
    try {
      final json = _queue.map((r) => r.toJson()).toList();
      await _file.writeAsString(jsonEncode(json));
    } catch (e) {
      _logger.error('PersistentQueueStore: failed to persist — $e');
    }
  }

  void _persistSync() {
    try {
      final json = _queue.map((r) => r.toJson()).toList();
      _file.writeAsStringSync(jsonEncode(json));
    } catch (e) {
      _logger.error('PersistentQueueStore: failed to persist sync — $e');
    }
  }
}
