import 'dart:math';

/// A timestamped aircraft fix used for display prediction.
class MotionFix {
  final DateTime time;
  final double lat;
  final double lon;
  final double? trackDeg;
  final double? groundSpeedKt;

  const MotionFix({
    required this.time,
    required this.lat,
    required this.lon,
    this.trackDeg,
    this.groundSpeedKt,
  });
}

/// Moves a marker smoothly between ADS-B fixes, which arrive seconds apart.
///
/// Between fixes the aircraft is advanced along its reported track at its
/// reported speed; when two fixes show it turning, the prediction follows a
/// constant-rate arc instead of a straight line, so a banking aircraft doesn't
/// cut the corner and then snap back. Prediction is capped so a lost signal
/// never sends a marker sailing on indefinitely.
///
/// The turn-rate estimate and arc integration follow God's Eye View's
/// motionModel.js (MIT), adapted there from skylight (MIT).
class MotionModel {
  MotionModel._();

  static const maxExtrapolation = Duration(seconds: 45);
  static const maxTurnRateDegPerSec = 6.0; // beyond a rate-2 turn: treat as noise

  /// Estimated turn rate in degrees per second from two consecutive fixes.
  static double turnRate(MotionFix previous, MotionFix latest) {
    final a = previous.trackDeg, b = latest.trackDeg;
    if (a == null || b == null) return 0;
    final seconds = latest.time.difference(previous.time).inMilliseconds / 1000;
    if (seconds <= 0.5) return 0;
    final delta = ((b - a + 540) % 360) - 180; // shortest signed difference
    final rate = delta / seconds;
    return rate.abs() > maxTurnRateDegPerSec ? 0 : rate;
  }

  /// Predicted position at [now] given the latest fix and (optionally) the
  /// one before it.
  static ({double lat, double lon, double trackDeg}) predict(
    MotionFix latest, {
    MotionFix? previous,
    DateTime? now,
  }) {
    final track = latest.trackDeg;
    final speed = latest.groundSpeedKt;
    if (track == null || speed == null || speed < 30) {
      return (lat: latest.lat, lon: latest.lon, trackDeg: track ?? 0);
    }

    var dt = (now ?? DateTime.now()).difference(latest.time).inMilliseconds / 1000;
    dt = dt.clamp(0, maxExtrapolation.inSeconds).toDouble();
    if (dt == 0) return (lat: latest.lat, lon: latest.lon, trackDeg: track);

    final metersPerSecond = speed * 0.514444;
    final rate = previous == null ? 0.0 : turnRate(previous, latest);

    // Integrate in one-second steps so the arc bends as the heading changes.
    var lat = latest.lat, lon = latest.lon, heading = track;
    var remaining = dt;
    while (remaining > 0) {
      final step = min(1.0, remaining);
      heading = (heading + rate * step) % 360;
      final dist = metersPerSecond * step;
      final next = _destination(lat, lon, heading, dist);
      lat = next.$1;
      lon = next.$2;
      remaining -= step;
    }
    return (lat: lat, lon: lon, trackDeg: heading);
  }

  static (double, double) _destination(double lat, double lon, double bearingDeg, double meters) {
    const r = 6371000.0;
    final d = meters / r;
    final b = bearingDeg * pi / 180;
    final p1 = lat * pi / 180, l1 = lon * pi / 180;
    final p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(b));
    final l2 = l1 + atan2(sin(b) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2));
    return (p2 * 180 / pi, ((l2 * 180 / pi + 540) % 360) - 180);
  }
}
