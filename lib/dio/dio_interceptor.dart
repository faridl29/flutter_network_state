/// Dio interceptor that integrates with [NetworkManager].
///
/// Attaches to a [Dio] instance to:
/// 1. Check connectivity before each request.
/// 2. Auto-retry failed requests with configurable backoff.
/// 3. Optionally queue requests for later when offline.
/// 4. Log request/response lifecycle.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_network_state/core/logger.dart';
import 'package:flutter_network_state/core/network_status.dart';
import 'package:flutter_network_state/core/retry_policy.dart';
import 'package:flutter_network_state/queue/request_queue.dart';

/// Configuration for [NetworkDioInterceptor].
class DioInterceptorConfig {
  const DioInterceptorConfig({
    this.retryPolicy = const RetryPolicy(),
    this.queueWhenOffline = true,
    this.logRequests = true,
    this.logResponses = true,
    this.logErrors = true,
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
  });

  /// Retry policy for failed requests.
  final RetryPolicy retryPolicy;

  /// When `true`, requests that fail because the device is offline are
  /// enqueued in the [RequestQueue] for later replay.
  final bool queueWhenOffline;

  /// Log outgoing requests.
  final bool logRequests;

  /// Log incoming responses.
  final bool logResponses;

  /// Log errors.
  final bool logErrors;

  /// HTTP status codes that are eligible for automatic retry.
  final Set<int> retryableStatusCodes;
}

/// A [Dio] interceptor powered by [flutter_network_state].
///
/// Usage:
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(
///   NetworkDioInterceptor(
///     monitor: networkManager.monitor,
///     queue: networkManager.queue,
///   ),
/// );
/// ```
class NetworkDioInterceptor extends Interceptor {
  NetworkDioInterceptor({
    required NetworkStatusMonitor monitor,
    RequestQueue? queue,
    DioInterceptorConfig? config,
    NetworkLogger? logger,
  })  : _monitor = monitor,
        _queue = queue,
        _config = config ?? const DioInterceptorConfig(),
        _logger = logger ?? NetworkLogger.defaultLogger;

  final NetworkStatusMonitor _monitor;
  final RequestQueue? _queue;
  final DioInterceptorConfig _config;
  final NetworkLogger _logger;

  static int _idCounter = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_config.logRequests) {
      _logger.debug(
        'DioInterceptor: → ${options.method} ${options.uri}',
      );
    }

    // If offline and queueing is enabled, reject early so the error handler
    // can enqueue.
    if (!_monitor.isOnline && _config.queueWhenOffline) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'Device is offline — request will be queued',
        ),
      );
      return;
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_config.logResponses) {
      _logger.debug(
        'DioInterceptor: ← ${response.statusCode} '
        '${response.requestOptions.method} ${response.requestOptions.uri}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_config.logErrors) {
      _logger.warning(
        'DioInterceptor: ✗ ${err.type.name} '
        '${err.requestOptions.method} ${err.requestOptions.uri}',
      );
    }

    // Check if the error is retryable.
    final isRetryable = _isRetryable(err);

    if (isRetryable) {
      // Attempt retry with backoff.
      final result = await _retryRequest(err.requestOptions);
      if (result != null) {
        handler.resolve(result);
        return;
      }
    }

    // Queue for later if offline.
    if (_config.queueWhenOffline &&
        _queue != null &&
        _isOfflineError(err)) {
      _enqueueRequest(err.requestOptions);
    }

    handler.next(err);
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  bool _isRetryable(DioException err) {
    if (err.type == DioExceptionType.cancel) return false;

    // Connection errors are retryable.
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    // Certain HTTP status codes are retryable.
    final statusCode = err.response?.statusCode;
    if (statusCode != null &&
        _config.retryableStatusCodes.contains(statusCode)) {
      return true;
    }

    return false;
  }

  bool _isOfflineError(DioException err) {
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout;
  }

  Future<Response<dynamic>?> _retryRequest(RequestOptions options) async {
    final policy = _config.retryPolicy;
    final dio = Dio(BaseOptions(
      baseUrl: options.baseUrl,
      connectTimeout: options.connectTimeout,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
    ));

    for (var attempt = 0; attempt < policy.maxRetries; attempt++) {
      final delay = policy.delayFor(attempt);
      _logger.debug(
        'DioInterceptor: retry ${attempt + 1}/${policy.maxRetries} '
        'in ${delay.inMilliseconds}ms',
      );
      await Future<void>.delayed(delay);

      // Only retry if still online.
      if (!_monitor.isOnline) return null;

      try {
        final response = await dio.request<dynamic>(
          options.path,
          data: options.data,
          queryParameters: options.queryParameters,
          options: Options(
            method: options.method,
            headers: options.headers,
            responseType: options.responseType,
            contentType: options.contentType,
          ),
        );
        _logger.info(
          'DioInterceptor: retry succeeded on attempt ${attempt + 1}',
        );
        return response;
      } catch (_) {
        // Continue to next attempt.
      }
    }

    return null;
  }

  void _enqueueRequest(RequestOptions options) {
    final id = 'dio_${++_idCounter}_${DateTime.now().millisecondsSinceEpoch}';

    _queue?.enqueue(
      QueuedRequest(
        id: id,
        cacheKey: options.extra['cacheKey'] as String?,
        retryPolicy: _config.retryPolicy,
        execute: () async {
          final dio = Dio(BaseOptions(
            baseUrl: options.baseUrl,
            connectTimeout: options.connectTimeout,
            receiveTimeout: options.receiveTimeout,
          ));
          return dio.request<dynamic>(
            options.path,
            data: options.data,
            queryParameters: options.queryParameters,
            options: Options(
              method: options.method,
              headers: options.headers,
              responseType: options.responseType,
              contentType: options.contentType,
            ),
          );
        },
      ),
    );

    _logger.info(
      'DioInterceptor: queued ${options.method} ${options.uri} '
      'for later replay',
    );
  }
}
