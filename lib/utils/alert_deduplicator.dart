import 'dart:collection';
import '../models/models.dart';

/// Prevents duplicate notifications within a time window.
///
/// Hashes (flightId, eventType, key_value) and skips
/// if an identical alert was generated within 30 minutes.
class AlertDeduplicator {
  final Duration window;
  final LinkedHashMap<String, DateTime> _recentAlerts = LinkedHashMap();

  AlertDeduplicator({this.window = const Duration(minutes: 30)});

  /// Returns true if this alert should be sent (not a duplicate).
  bool shouldSend(AlertEvent alert) {
    final key = _buildKey(alert);
    final now = DateTime.now();

    // Clean expired entries
    _recentAlerts.removeWhere((_, timestamp) =>
        now.difference(timestamp) > window);

    if (_recentAlerts.containsKey(key)) {
      return false; // Duplicate within window
    }

    _recentAlerts[key] = now;
    return true;
  }

  /// Build a dedup key from the alert's distinguishing properties.
  String _buildKey(AlertEvent alert) {
    final keyValue = _extractKeyValue(alert);
    return '${alert.flightId}:${alert.eventType.name}:$keyValue';
  }

  String _extractKeyValue(AlertEvent alert) {
    final meta = alert.metadata;
    switch (alert.eventType) {
      case AlertEventType.gateChange:
        return meta?['new_gate']?.toString() ?? '';
      case AlertEventType.terminalChange:
        return meta?['new_terminal']?.toString() ?? '';
      case AlertEventType.departureDelay:
      case AlertEventType.arrivalDelay:
        // Bucket delays to nearest 15 min to avoid spam
        final delay = meta?['delay_minutes'] as int? ?? 0;
        return '${(delay ~/ 15) * 15}';
      case AlertEventType.cancellation:
      case AlertEventType.diversion:
      case AlertEventType.landed:
      case AlertEventType.baggageClaim:
      case AlertEventType.connectionRisk:
      case AlertEventType.quotaExhausted:
        return alert.eventType.name;
    }
  }

  /// Clear all tracked alerts (for testing).
  void clear() => _recentAlerts.clear();

  /// Number of alerts currently tracked.
  int get trackedCount => _recentAlerts.length;
}
