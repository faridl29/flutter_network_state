/// Lightweight logging abstraction for the plugin.
///
/// By default logs to `print()` with a `[flutter_network_state]` tag. Users
/// can replace or suppress the logger via [NetworkLogger.custom] or
/// [NetworkLogger.silent].
library;

/// Log level severity.
enum LogLevel {
  /// Fine-grained debugging information.
  debug,

  /// General informational messages.
  info,

  /// Potential issues that don't prevent operation.
  warning,

  /// Critical failures.
  error,
}

/// Pluggable logger used across the entire plugin.
///
/// ```dart
/// // Silence all logs
/// final manager = NetworkManager(
///   logger: NetworkLogger.silent,
/// );
///
/// // Provide a custom logger (e.g. to forward to Crashlytics)
/// final manager = NetworkManager(
///   logger: NetworkLogger.custom((level, message) {
///     FirebaseCrashlytics.instance.log('[$level] $message');
///   }),
/// );
/// ```
class NetworkLogger {
  /// Creates a logger with a custom handler.
  const NetworkLogger.custom(this._handler, {this.minLevel = LogLevel.debug});

  /// The default logger that prints to stdout.
  static final NetworkLogger defaultLogger = NetworkLogger.custom(
    (level, message) {
      // ignore: avoid_print
      print('[flutter_network_state][${level.name.toUpperCase()}] $message');
    },
  );

  /// A silent logger that discards all messages.
  static final NetworkLogger silent = NetworkLogger.custom(
    (_, __) {},
    minLevel: LogLevel.error,
  );

  final void Function(LogLevel level, String message) _handler;

  /// Minimum log level to forward. Messages below this are dropped.
  final LogLevel minLevel;

  // ---------------------------------------------------------------------------
  // Convenience methods
  // ---------------------------------------------------------------------------

  /// Log a debug message.
  void debug(String message) => _log(LogLevel.debug, message);

  /// Log an informational message.
  void info(String message) => _log(LogLevel.info, message);

  /// Log a warning.
  void warning(String message) => _log(LogLevel.warning, message);

  /// Log an error.
  void error(String message) => _log(LogLevel.error, message);

  void _log(LogLevel level, String message) {
    if (level.index >= minLevel.index) {
      _handler(level, message);
    }
  }
}
