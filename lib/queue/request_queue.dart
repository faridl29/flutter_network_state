/// Offline request queue that stores failed / deferred requests and replays
/// them when connectivity is restored.
///
/// The default implementation is in-memory. For persistence across app
/// restarts, implement [QueueStore] with a database-backed store.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter_network_state/core/logger.dart';
import 'package:flutter_network_state/core/retry_policy.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Queued request model
// ---------------------------------------------------------------------------

/// Represents a single deferred request waiting in the queue.
@immutable
class QueuedRequest {
  QueuedRequest({
    required this.id,
    required this.execute,
    this.retryPolicy = const RetryPolicy(),
    this.cacheKey,
    DateTime? enqueuedAt,
  }) : enqueuedAt = enqueuedAt ?? DateTime.now();

  /// Unique identifier for this request.
  final String id;

  /// The closure that executes the actual request.
  final Future<dynamic> Function() execute;

  /// Retry policy to apply when replaying this request.
  final RetryPolicy retryPolicy;

  /// Optional cache key — if provided, the result will be cached on success.
  final String? cacheKey;

  /// When this request was added to the queue.
  final DateTime enqueuedAt;

  @override
  String toString() => 'QueuedRequest(id: $id, cacheKey: $cacheKey)';
}

/// Result of processing a single queued request.
@immutable
class QueueProcessResult {
  const QueueProcessResult({
    required this.request,
    required this.isSuccess,
    this.data,
    this.error,
  });

  final QueuedRequest request;
  final bool isSuccess;
  final dynamic data;
  final Object? error;
}

// ---------------------------------------------------------------------------
// Queue store abstraction
// ---------------------------------------------------------------------------

/// Abstraction for queue persistence. The default [InMemoryQueueStore] does
/// NOT survive app restarts.
abstract class QueueStore {
  /// Add a request to the end of the queue.
  void enqueue(QueuedRequest request);

  /// Remove and return the next request, or `null` if empty.
  QueuedRequest? dequeue();

  /// Peek at the next request without removing it.
  QueuedRequest? peek();

  /// Remove a specific request by its [id].
  bool remove(String id);

  /// All requests currently in the queue (oldest first).
  List<QueuedRequest> get all;

  /// Number of queued requests.
  int get length;

  /// Whether the queue is empty.
  bool get isEmpty;

  /// Clear all queued requests.
  void clear();
}

/// Simple in-memory FIFO queue.
class InMemoryQueueStore implements QueueStore {
  final Queue<QueuedRequest> _queue = Queue<QueuedRequest>();

  @override
  void enqueue(QueuedRequest request) => _queue.add(request);

  @override
  QueuedRequest? dequeue() => _queue.isEmpty ? null : _queue.removeFirst();

  @override
  QueuedRequest? peek() => _queue.isEmpty ? null : _queue.first;

  @override
  bool remove(String id) {
    final before = _queue.length;
    _queue.removeWhere((r) => r.id == id);
    return _queue.length < before;
  }

  @override
  List<QueuedRequest> get all => List.unmodifiable(_queue);

  @override
  int get length => _queue.length;

  @override
  bool get isEmpty => _queue.isEmpty;

  @override
  void clear() => _queue.clear();
}

// ---------------------------------------------------------------------------
// Request queue
// ---------------------------------------------------------------------------

/// Manages a FIFO queue of network requests that should be replayed when
/// the device regains connectivity.
///
/// The queue itself does NOT listen for connectivity — that is the
/// responsibility of [SyncEngine] which calls [processQueue] at the right
/// time.
class RequestQueue {
  /// Creates a [RequestQueue].
  RequestQueue({
    QueueStore? store,
    NetworkLogger? logger,
  })  : _store = store ?? InMemoryQueueStore(),
        _logger = logger ?? NetworkLogger.defaultLogger;

  final QueueStore _store;
  final NetworkLogger _logger;

  /// Whether the queue is currently being processed.
  bool _isProcessing = false;

  /// Stream of processing results emitted as each queued request completes.
  final _resultController =
      StreamController<QueueProcessResult>.broadcast();

  /// Stream that emits a [QueueProcessResult] for every request processed.
  Stream<QueueProcessResult> get resultStream => _resultController.stream;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Enqueue a new request.
  void enqueue(QueuedRequest request) {
    _store.enqueue(request);
    _logger.info(
      'RequestQueue: enqueued "${request.id}" '
      '(queue size: ${_store.length})',
    );
  }

  /// Number of requests waiting.
  int get length => _store.length;

  /// Whether the queue is empty.
  bool get isEmpty => _store.isEmpty;

  /// All queued requests (read-only snapshot).
  List<QueuedRequest> get pending => _store.all;

  /// Whether the queue is currently being drained.
  bool get isProcessing => _isProcessing;

  /// Remove a specific request by [id].
  bool remove(String id) {
    final removed = _store.remove(id);
    if (removed) {
      _logger.debug('RequestQueue: removed "$id"');
    }
    return removed;
  }

  /// Discard all queued requests.
  void clear() {
    _store.clear();
    _logger.info('RequestQueue: cleared');
  }

  /// Process all queued requests sequentially.
  ///
  /// Returns a list of [QueueProcessResult]s. Failed requests that still
  /// have remaining retries are re-enqueued at the back of the queue.
  ///
  /// The optional [onProgress] callback is invoked after each request with
  /// the (completed, total) counts.
  Future<List<QueueProcessResult>> processQueue({
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_isProcessing) {
      _logger.warning('RequestQueue: processQueue called while already '
          'processing — skipping');
      return [];
    }

    _isProcessing = true;
    final results = <QueueProcessResult>[];
    final total = _store.length;

    _logger.info('RequestQueue: processing $total queued request(s)');

    var completed = 0;

    while (!_store.isEmpty) {
      final request = _store.dequeue()!;
      try {
        final data = await _executeWithRetry(request);
        final result = QueueProcessResult(
          request: request,
          isSuccess: true,
          data: data,
        );
        results.add(result);
        if (!_resultController.isClosed) _resultController.add(result);
        _logger.info('RequestQueue: ✓ "${request.id}" succeeded');
      } catch (e) {
        final result = QueueProcessResult(
          request: request,
          isSuccess: false,
          error: e,
        );
        results.add(result);
        if (!_resultController.isClosed) _resultController.add(result);
        _logger.warning('RequestQueue: ✗ "${request.id}" failed — $e');
      }

      completed++;
      onProgress?.call(completed, total);
    }

    _isProcessing = false;
    _logger.info(
      'RequestQueue: processing complete — '
      '${results.where((r) => r.isSuccess).length}/$total succeeded',
    );
    return results;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _resultController.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Executes a request with its configured [RetryPolicy].
  Future<dynamic> _executeWithRetry(QueuedRequest request) async {
    final policy = request.retryPolicy;
    Object? lastError;

    for (var attempt = 0; attempt <= policy.maxRetries; attempt++) {
      try {
        return await request.execute();
      } catch (e) {
        lastError = e;

        // Check if we should retry.
        final shouldRetry = policy.shouldRetry?.call(e, attempt) ?? true;
        if (!shouldRetry || !policy.canRetry(attempt + 1)) {
          break;
        }

        final delay = policy.delayFor(attempt);
        _logger.debug(
          'RequestQueue: retrying "${request.id}" in '
          '${delay.inMilliseconds}ms (attempt ${attempt + 1}/${policy.maxRetries})',
        );
        await Future<void>.delayed(delay);
      }
    }

    throw lastError!;
  }
}
