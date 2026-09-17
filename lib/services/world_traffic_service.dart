import 'package:flutter/foundation.dart';

import 'data_gateway.dart';

/// Where a traffic snapshot came from, so the UI can label it honestly.
enum TrafficSource { openSkyGlobal, adsbRegional, adsbMilitary }

/// One aircraft in a traffic snapshot, normalised across OpenSky and adsb.lol.
class TrafficAircraft {
  final String hex;
  final String callsign;
  final double lat;
  final double lon;
  final double? altitudeFt;
  final double? trackDeg;
  final double? groundSpeedKt;
  final double? verticalRateFpm;
  final bool onGround;
  final bool military;
  final String? registration;
  final String? typeCode;
  final String? typeDescription;

  /// ADS-B emitter category ("A1".."B7") when known.
  final String? category;
  final TrafficSource source;

  const TrafficAircraft({
    required this.hex,
    required this.callsign,
    required this.lat,
    required this.lon,
    required this.source,
    this.altitudeFt,
    this.trackDeg,
    this.groundSpeedKt,
    this.verticalRateFpm,
    this.onGround = false,
    this.military = false,
    this.registration,
    this.typeCode,
    this.typeDescription,
    this.category,
  });

  String get label => callsign.isNotEmpty ? callsign : (registration ?? hex.toUpperCase());

  TrafficAircraft asMilitary() => TrafficAircraft(
        hex: hex, callsign: callsign, lat: lat, lon: lon, source: source,
        altitudeFt: altitudeFt, trackDeg: trackDeg, groundSpeedKt: groundSpeedKt,
        verticalRateFpm: verticalRateFpm, onGround: onGround, military: true,
        registration: registration, typeCode: typeCode, typeDescription: typeDescription,
        category: category,
      );

  /// adsb.lol / readsb record.
  static TrafficAircraft? fromAdsb(Map<String, dynamic> a, TrafficSource source) {
    final hex = (a['hex'] as String?)?.trim();
    final lat = (a['lat'] as num?)?.toDouble();
    final lon = (a['lon'] as num?)?.toDouble();
    if (hex == null || hex.isEmpty || lat == null || lon == null) return null;
    final alt = a['alt_baro'];
    // readsb dbFlags bit 0 marks military airframes.
    final dbFlags = (a['dbFlags'] as num?)?.toInt() ?? 0;
    return TrafficAircraft(
      hex: hex.replaceAll('~', ''),
      callsign: (a['flight'] as String? ?? '').trim(),
      lat: lat,
      lon: lon,
      source: source,
      altitudeFt: alt is num ? alt.toDouble() : null,
      onGround: alt == 'ground',
      trackDeg: (a['track'] as num?)?.toDouble() ?? (a['true_heading'] as num?)?.toDouble(),
      groundSpeedKt: (a['gs'] as num?)?.toDouble(),
      verticalRateFpm: (a['baro_rate'] as num?)?.toDouble() ?? (a['geom_rate'] as num?)?.toDouble(),
      military: source == TrafficSource.adsbMilitary || (dbFlags & 1) == 1,
      registration: (a['r'] as String?)?.trim(),
      typeCode: (a['t'] as String?)?.trim(),
      typeDescription: (a['desc'] as String?)?.trim(),
      category: a['category'] as String?,
    );
  }

  /// OpenSky state vector, or the compact row the world-traffic function
  /// writes: [hex, callsign, lat, lon, altM, trackDeg, velocityMs, onGround,
  /// vertRateMs, category, lastContact].
  static TrafficAircraft? fromCompact(List row) {
    final lat = (row[2] as num?)?.toDouble();
    final lon = (row[3] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final altM = (row[4] as num?)?.toDouble();
    final velMs = (row[6] as num?)?.toDouble();
    final vrMs = (row[8] as num?)?.toDouble();
    return TrafficAircraft(
      hex: row[0] as String,
      callsign: (row[1] as String? ?? '').trim(),
      lat: lat,
      lon: lon,
      source: TrafficSource.openSkyGlobal,
      altitudeFt: altM == null ? null : altM * 3.28084,
      trackDeg: (row[5] as num?)?.toDouble(),
      groundSpeedKt: velMs == null ? null : velMs * 1.94384,
      verticalRateFpm: vrMs == null ? null : vrMs * 196.85,
      onGround: row[7] == 1 || row[7] == true,
      category: _openSkyCategory((row[9] as num?)?.toInt()),
    );
  }

  static List? stateVectorToCompact(List s) => [
        s[0], s[1], s[6], s[5], s[7], s[10], s[9], s[8] == true ? 1 : 0, s[11],
        s.length > 17 ? s[17] : null, s[4],
      ];

  // OpenSky's extended category index to the ADS-B emitter category string.
  static String? _openSkyCategory(int? c) => switch (c) {
        2 => 'A1', 3 => 'A2', 4 => 'A3', 5 => 'A4', 6 => 'A5', 7 => 'A6', 8 => 'A7',
        9 => 'B1', 10 => 'B2', 11 => 'B3', 12 => 'B4', 14 => 'B6', 15 => 'B7',
        _ => null,
      };
}

class TrafficSnapshot {
  final List<TrafficAircraft> aircraft;
  final DateTime fetchedAt;
  final TrafficSource source;

  /// Set when the snapshot could not be refreshed, in words a user can act on.
  final String? limitation;

  const TrafficSnapshot(this.aircraft, this.fetchedAt, this.source, {this.limitation});

  Duration get age => DateTime.now().difference(fetchedAt);
}

/// Live aircraft for the World view.
///
/// * Zoomed in: adsb.lol within 250 nm of the map centre — live, seconds old.
/// * Whole world on a native build: OpenSky's global feed, downloaded by the
///   device itself (OpenSky throttles anonymous requests from cloud servers,
///   but a phone on a normal connection is fine). Anonymous access allows about
///   100 global downloads a day per network, so refreshes are spaced out.
/// * Whole world on web: the shared snapshot from the world-traffic function,
///   which needs OpenSky credentials configured on the backend.
class WorldTrafficService {
  WorldTrafficService._();
  static final WorldTrafficService instance = WorldTrafficService._();

  static const globalRefresh = Duration(minutes: 2);

  TrafficSnapshot? _global;
  Future<TrafficSnapshot?>? _globalLoading;
  final _regional = <String, TrafficSnapshot>{};
  TrafficSnapshot? _military;

  Future<TrafficSnapshot?> global() {
    if (_global != null && _global!.age < globalRefresh) return Future.value(_global);
    return _globalLoading ??= _loadGlobal().whenComplete(() => _globalLoading = null);
  }

  Future<TrafficSnapshot?> _loadGlobal() async {
    if (!kIsWeb) {
      final body = await DataGateway.instance.getJson(
        'https://opensky-network.org/api/states/all?extended=1',
        timeout: const Duration(seconds: 60),
      );
      final states = body is Map ? body['states'] as List? : null;
      if (states != null) {
        final aircraft = states
            .map((s) => TrafficAircraft.fromCompact(TrafficAircraft.stateVectorToCompact(s as List)!))
            .whereType<TrafficAircraft>()
            .toList(growable: false);
        return _global = TrafficSnapshot(aircraft, DateTime.now(), TrafficSource.openSkyGlobal);
      }
      return _global ??
          TrafficSnapshot(const [], DateTime.now(), TrafficSource.openSkyGlobal,
              limitation: 'OpenSky did not respond. Zoom in for live regional traffic.');
    }

    final meta = await DataGateway.instance.function('world-traffic');
    if (meta is! Map || meta['available'] != true) {
      return TrafficSnapshot(const [], DateTime.now(), TrafficSource.openSkyGlobal,
          limitation: 'Worldwide traffic on the web needs OpenSky credentials on the server. '
              'Zoom in for live regional traffic, or use the mobile app.');
    }
    final body = await DataGateway.instance.getJson(meta['url'] as String, timeout: const Duration(seconds: 60));
    final rows = body is Map ? body['aircraft'] as List? : null;
    if (rows == null) return _global;
    final aircraft = rows
        .map((r) => TrafficAircraft.fromCompact(r as List))
        .whereType<TrafficAircraft>()
        .toList(growable: false);
    final fetchedAt = DateTime.tryParse('${meta['fetchedAt']}') ?? DateTime.now();
    return _global = TrafficSnapshot(aircraft, fetchedAt, TrafficSource.openSkyGlobal);
  }

  /// Live traffic within [radiusNm] (max 250) of a point.
  Future<TrafficSnapshot?> regional(double lat, double lon, {int radiusNm = 250}) async {
    final key = '${lat.toStringAsFixed(1)},${lon.toStringAsFixed(1)},$radiusNm';
    final hit = _regional[key];
    if (hit != null && hit.age < const Duration(seconds: 10)) return hit;

    final data = await DataGateway.instance.proxy('adsb-radius', {
      'lat': lat,
      'lon': lon,
      'dist': radiusNm.clamp(1, 250),
    });
    final list = data is Map ? data['ac'] as List? : null;
    if (list == null) return hit;
    final snapshot = TrafficSnapshot(
      list
          .whereType<Map<String, dynamic>>()
          .map((a) => TrafficAircraft.fromAdsb(a, TrafficSource.adsbRegional))
          .whereType<TrafficAircraft>()
          .toList(growable: false),
      DateTime.now(),
      TrafficSource.adsbRegional,
    );
    if (_regional.length > 30) _regional.remove(_regional.keys.first);
    return _regional[key] = snapshot;
  }

  /// Every aircraft currently transmitting as military, worldwide.
  Future<TrafficSnapshot?> military() async {
    if (_military != null && _military!.age < const Duration(seconds: 20)) return _military;
    final data = await DataGateway.instance.proxy('adsb-mil');
    final list = data is Map ? data['ac'] as List? : null;
    if (list == null) return _military;
    return _military = TrafficSnapshot(
      list
          .whereType<Map<String, dynamic>>()
          .map((a) => TrafficAircraft.fromAdsb(a, TrafficSource.adsbMilitary))
          .whereType<TrafficAircraft>()
          .toList(growable: false),
      DateTime.now(),
      TrafficSource.adsbMilitary,
    );
  }

  /// Current position of an airframe by tail number ("where's my plane").
  Future<TrafficAircraft?> byRegistration(String registration) async {
    final reg = registration.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]{2,10}$').hasMatch(reg)) return null;
    final data = await DataGateway.instance.proxy('adsb-reg', {'reg': reg});
    final list = data is Map ? data['ac'] as List? : null;
    if (list == null || list.isEmpty) return null;
    return TrafficAircraft.fromAdsb(list.first as Map<String, dynamic>, TrafficSource.adsbRegional);
  }
}
