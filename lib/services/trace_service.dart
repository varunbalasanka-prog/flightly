import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_gateway.dart';

/// One recorded position from an aircraft's real flown path.
class TracePoint {
  final DateTime time;
  final double lat;
  final double lon;

  /// Barometric altitude in feet; null while on the ground.
  final double? altitudeFt;
  final double? groundSpeedKt;
  final double? trackDeg;

  const TracePoint({
    required this.time,
    required this.lat,
    required this.lon,
    this.altitudeFt,
    this.groundSpeedKt,
    this.trackDeg,
  });

  List<dynamic> toRow() => [time.millisecondsSinceEpoch ~/ 1000, lat, lon, altitudeFt, groundSpeedKt, trackDeg];

  static TracePoint fromRow(List r) => TracePoint(
        time: DateTime.fromMillisecondsSinceEpoch((r[0] as num).toInt() * 1000),
        lat: (r[1] as num).toDouble(),
        lon: (r[2] as num).toDouble(),
        altitudeFt: (r[3] as num?)?.toDouble(),
        groundSpeedKt: (r[4] as num?)?.toDouble(),
        trackDeg: (r[5] as num?)?.toDouble(),
      );
}

/// Real flown paths from adsb.lol's trace archive (ODbL — credit
/// "adsb.lol" wherever a trace is drawn).
///
/// adsb.lol keeps roughly the last 24 hours per aircraft. To let a traveller
/// replay a flight later, the trace is copied into `flight_tracks` the first
/// time it is fetched for one of their flights.
class TraceService {
  TraceService._();
  static final TraceService instance = TraceService._();

  final _cache = <String, Cached<List<TracePoint>>>{};

  /// The recorded path for a Mode-S hex, oldest first. Empty if none.
  Future<List<TracePoint>> trace(String modeSHex) async {
    final hex = modeSHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) return const [];
    final hit = _cache[hex];
    if (hit != null && hit.fresherThan(const Duration(minutes: 1))) return hit.value;

    final data = await DataGateway.instance.proxy('adsb-trace', {'hex': hex});
    if (data is! Map) return hit?.value ?? const [];

    // readsb trace format: timestamp base + rows of
    // [secondsOffset, lat, lon, altFt|"ground"|null, gsKt, trackDeg, flags, ...]
    final base = (data['timestamp'] as num?)?.toDouble() ?? 0;
    final points = <TracePoint>[];
    for (final row in (data['trace'] as List? ?? const [])) {
      if (row is! List || row.length < 6) continue;
      final lat = (row[1] as num?)?.toDouble();
      final lon = (row[2] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final alt = row[3];
      points.add(TracePoint(
        time: DateTime.fromMillisecondsSinceEpoch(((base + (row[0] as num).toDouble()) * 1000).round()),
        lat: lat,
        lon: lon,
        altitudeFt: alt is num ? alt.toDouble() : null,
        groundSpeedKt: (row[4] as num?)?.toDouble(),
        trackDeg: (row[5] as num?)?.toDouble(),
      ));
    }
    _cache[hex] = Cached(points);
    return points;
  }

  /// Segment of [points] that belongs to the most recent flight: the trace
  /// archive runs across several legs, split where the aircraft sat still or
  /// went silent for a long time.
  static List<TracePoint> lastLeg(List<TracePoint> points) {
    if (points.length < 2) return points;
    var start = 0;
    for (var i = 1; i < points.length; i++) {
      final gap = points[i].time.difference(points[i - 1].time);
      final wasOnGround = points[i - 1].altitudeFt == null;
      if (gap > const Duration(minutes: 40) || (wasOnGround && gap > const Duration(minutes: 10))) {
        start = i;
      }
    }
    return points.sublist(start);
  }

  Future<void> saveForFlight(String flightId, List<TracePoint> points) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || points.isEmpty) return;
    try {
      await Supabase.instance.client.from('flight_tracks').upsert({
        'flight_id': flightId,
        'user_id': user.id,
        'points': points.map((p) => p.toRow()).toList(),
        'source': 'adsb.lol',
        'captured_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Saving flight track failed: $e');
    }
  }

  Future<List<TracePoint>> savedForFlight(String flightId) async {
    try {
      final row = await Supabase.instance.client
          .from('flight_tracks')
          .select('points')
          .eq('flight_id', flightId)
          .maybeSingle();
      final rows = row?['points'] as List?;
      return rows == null ? const [] : rows.map((r) => TracePoint.fromRow(r as List)).toList();
    } catch (_) {
      return const [];
    }
  }
}
