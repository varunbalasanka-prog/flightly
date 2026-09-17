import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

/// An airport from the bundled OurAirports directory (public domain).
class AirportInfoRecord {
  final String iata;
  final String icao;
  final String name;
  final String city;
  final String countryCode;
  final double lat;
  final double lon;

  /// 'L' large, 'M' medium, 'S' small (scheduled service only).
  final String size;

  const AirportInfoRecord({
    required this.iata,
    required this.icao,
    required this.name,
    required this.city,
    required this.countryCode,
    required this.lat,
    required this.lon,
    required this.size,
  });

  String get displayCity => city.isNotEmpty ? city : name;
}

/// Every airport with an IATA code and scheduled service — about 5,300 —
/// resolvable by IATA or ICAO without a network call.
///
/// Replaces the hard-coded 19-airport table for anything that needs real
/// coordinates or an ICAO code (weather lookups, maps, drive times).
class AirportDirectory {
  AirportDirectory._();
  static final AirportDirectory instance = AirportDirectory._();

  final Map<String, AirportInfoRecord> _byIata = {};
  final Map<String, AirportInfoRecord> _byIcao = {};
  Future<void>? _loading;

  bool get isLoaded => _byIata.isNotEmpty;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/data/airports.json');
    final body = jsonDecode(raw) as Map<String, dynamic>;
    for (final row in body['airports'] as List) {
      final r = row as List;
      final airport = AirportInfoRecord(
        iata: r[0] as String,
        icao: r[1] as String,
        name: r[2] as String,
        city: r[3] as String,
        countryCode: r[4] as String,
        lat: (r[5] as num).toDouble(),
        lon: (r[6] as num).toDouble(),
        size: r[7] as String,
      );
      _byIata[airport.iata] = airport;
      if (airport.icao.length == 4) _byIcao[airport.icao] = airport;
    }
  }

  /// Synchronous lookup; returns null until [ensureLoaded] has completed.
  AirportInfoRecord? byIata(String? iata) =>
      iata == null ? null : _byIata[iata.trim().toUpperCase()];

  AirportInfoRecord? byIcao(String? icao) =>
      icao == null ? null : _byIcao[icao.trim().toUpperCase()];

  Future<AirportInfoRecord?> lookup(String code) async {
    await ensureLoaded();
    final c = code.trim().toUpperCase();
    return c.length == 4 ? byIcao(c) ?? byIata(c) : byIata(c) ?? byIcao(c);
  }

  /// Nearest airports to a point, largest first among ties within [radiusKm].
  Future<List<AirportInfoRecord>> nearest(
    double lat,
    double lon, {
    double radiusKm = 80,
    int limit = 5,
  }) async {
    await ensureLoaded();
    final hits = <(double, AirportInfoRecord)>[];
    for (final a in _byIata.values) {
      final d = haversineKm(lat, lon, a.lat, a.lon);
      if (d <= radiusKm) hits.add((d, a));
    }
    hits.sort((x, y) => x.$1.compareTo(y.$1));
    return hits.take(limit).map((h) => h.$2).toList();
  }
}

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}
