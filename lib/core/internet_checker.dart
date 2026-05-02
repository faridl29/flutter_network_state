/// Real internet connectivity verification.
///
/// Unlike [connectivity_plus] which only checks if a network interface is
/// available (WiFi connected, mobile data on), this module actually verifies
/// that the device can reach the internet by performing a lightweight
/// DNS lookup or HTTP HEAD request.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_network_state/core/logger.dart';

/// Configuration for [InternetChecker].
class InternetCheckerConfig {
  const InternetCheckerConfig({
    this.lookupAddresses = const ['google.com', 'cloudflare.com', 'apple.com'],
    this.timeout = const Duration(seconds: 3),
    this.checkInterval = const Duration(seconds: 10),
  });

  /// Domains to perform DNS lookups against.
  /// At least one must resolve for the device to be considered online.
  final List<String> lookupAddresses;

  /// Timeout for each DNS lookup attempt.
  final Duration timeout;

  /// Interval for periodic checks (used by [startPeriodicCheck]).
  final Duration checkInterval;
}

/// Performs real internet reachability checks via DNS lookup.
///
/// This is more reliable than `connectivity_plus` alone, which only checks
/// if a network interface is available — not whether the internet is
/// actually reachable (e.g. captive portal, firewall, DNS failure).
///
/// ```dart
/// final checker = InternetChecker();
///
/// // One-shot check
/// final isOnline = await checker.hasInternetAccess();
///
/// // Periodic stream
/// checker.startPeriodicCheck();
/// checker.statusStream.listen((isOnline) {
///   print('Internet: $isOnline');
/// });
/// ```
class InternetChecker {
  InternetChecker({
    InternetCheckerConfig? config,
    NetworkLogger? logger,
  })  : _config = config ?? const InternetCheckerConfig(),
        _logger = logger ?? NetworkLogger.defaultLogger;

  final InternetCheckerConfig _config;
  final NetworkLogger _logger;

  Timer? _timer;
  bool _lastResult = true;
  final _controller = StreamController<bool>.broadcast();

  /// Stream of internet reachability changes (deduped).
  Stream<bool> get statusStream => _controller.stream;

  /// Last known internet reachability result.
  bool get lastResult => _lastResult;

  /// Perform a one-shot internet reachability check.
  ///
  /// Tries DNS lookups against configured addresses. Returns `true` if
  /// at least one resolves successfully.
  Future<bool> hasInternetAccess() async {
    for (final address in _config.lookupAddresses) {
      try {
        final result = await InternetAddress.lookup(address)
            .timeout(_config.timeout);
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          _logger.debug('InternetChecker: DNS lookup for $address succeeded');
          return _update(true);
        }
      } on SocketException catch (_) {
        _logger.debug('InternetChecker: DNS lookup for $address failed');
      } on TimeoutException catch (_) {
        _logger.debug('InternetChecker: DNS lookup for $address timed out');
      }
    }

    _logger.warning('InternetChecker: all DNS lookups failed — no internet');
    return _update(false);
  }

  /// Start periodic internet checks.
  ///
  /// Results are emitted on [statusStream] only when the status changes.
  void startPeriodicCheck() {
    _timer?.cancel();
    _timer = Timer.periodic(_config.checkInterval, (_) => hasInternetAccess());
    // Immediate first check
    hasInternetAccess();
  }

  /// Stop periodic checks.
  void stopPeriodicCheck() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    stopPeriodicCheck();
    await _controller.close();
  }

  bool _update(bool isOnline) {
    if (isOnline != _lastResult) {
      _lastResult = isOnline;
      if (!_controller.isClosed) {
        _controller.add(isOnline);
      }
    }
    return isOnline;
  }
}
