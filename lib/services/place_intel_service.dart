import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'airport_directory.dart';
import 'data_gateway.dart';

// ── News ──────────────────────────────────────────────────────────────────

class NewsArticle {
  final String title;
  final String url;
  final String source;
  final DateTime? published;
  const NewsArticle(this.title, this.url, this.source, this.published);
}

class NewsService {
  NewsService._();
  static final NewsService instance = NewsService._();

  final _cache = <String, Cached<List<NewsArticle>>>{};

  /// Recent headlines mentioning [place], via Google News RSS parsed server-side.
  Future<List<NewsArticle>> about(String place) async {
    final q = place.trim();
    if (q.length < 2) return const [];
    final hit = _cache[q];
    if (hit != null && hit.fresherThan(const Duration(minutes: 20))) return hit.value;

    final data = await DataGateway.instance.proxy('news', {'query': q});
    final articles = <NewsArticle>[];
    for (final a in (data is Map ? data['articles'] as List? : null) ?? const []) {
      final m = a as Map;
      final title = (m['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      articles.add(NewsArticle(title, m['url'] as String? ?? '', m['source'] as String? ?? '',
          _parseRfc822(m['published'] as String?)));
    }
    _cache[q] = Cached(articles);
    return articles;
  }

  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  /// "Wed, 16 Sep 2026 14:31:36 GMT"
  static DateTime? _parseRfc822(String? s) {
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})').firstMatch(s ?? '');
    final month = _months[m?.group(2)];
    if (m == null || month == null) return null;
    return DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!),
        int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
  }
}

// ── Earthquakes (disruption signal) ──────────────────────────────────────

class Earthquake {
  final String place;
  final double magnitude;
  final double lat;
  final double lon;
  final DateTime time;
  final String url;
  const Earthquake(this.place, this.magnitude, this.lat, this.lon, this.time, this.url);
}

class DisruptionService {
  DisruptionService._();
  static final DisruptionService instance = DisruptionService._();

  Cached<List<Earthquake>>? _quakes;

  /// USGS: magnitude 2.5+ in the last 24 hours, worldwide.
  Future<List<Earthquake>> earthquakes() async {
    if (_quakes != null && _quakes!.fresherThan(const Duration(minutes: 10))) return _quakes!.value;
    final data = await DataGateway.instance.getJson(
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson',
    );
    final quakes = <Earthquake>[];
    for (final f in (data is Map ? data['features'] as List? : null) ?? const []) {
      final p = (f as Map)['properties'] as Map;
      final c = (f['geometry'] as Map)['coordinates'] as List;
      final mag = (p['mag'] as num?)?.toDouble();
      if (mag == null) continue;
      quakes.add(Earthquake(
        p['place'] as String? ?? 'Unknown location',
        mag,
        (c[1] as num).toDouble(),
        (c[0] as num).toDouble(),
        DateTime.fromMillisecondsSinceEpoch((p['time'] as num).toInt()),
        p['url'] as String? ?? '',
      ));
    }
    _quakes = Cached(quakes);
    return quakes;
  }

  /// Quakes large and close enough to plausibly affect an airport.
  Future<List<Earthquake>> near(double lat, double lon, {double radiusKm = 300, double minMagnitude = 4.5}) async {
    final all = await earthquakes();
    return all
        .where((q) => q.magnitude >= minMagnitude && haversineKm(lat, lon, q.lat, q.lon) <= radiusKm)
        .toList();
  }
}

// ── Drive time to the airport ─────────────────────────────────────────────

class DriveEstimate {
  final double distanceKm;
  final Duration duration;
  const DriveEstimate(this.distanceKm, this.duration);
}

class RoutingService {
  RoutingService._();
  static final RoutingService instance = RoutingService._();

  /// The device's current position, asking for permission if needed.
  /// Returns null if the user declines or location is unavailable.
  Future<Position?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  /// Driving estimate from OSRM on the OpenStreetMap community servers. It
  /// knows the road network, not live traffic, so treat it as a lower bound.
  Future<DriveEstimate?> drive(double fromLat, double fromLon, double toLat, double toLon) async {
    final data = await DataGateway.instance.getJson(
      'https://routing.openstreetmap.de/routed-car/route/v1/driving/'
      '${fromLon.toStringAsFixed(5)},${fromLat.toStringAsFixed(5)};'
      '${toLon.toStringAsFixed(5)},${toLat.toStringAsFixed(5)}?overview=false',
    );
    final routes = data is Map ? data['routes'] as List? : null;
    if (routes == null || routes.isEmpty) return null;
    final r = routes.first as Map;
    return DriveEstimate(
      (r['distance'] as num).toDouble() / 1000,
      Duration(seconds: (r['duration'] as num).round()),
    );
  }
}

// ── Satellites ────────────────────────────────────────────────────────────

class SatellitePosition {
  final String name;
  final int noradId;
  final double lat;
  final double lon;
  final double altitudeKm;
  const SatellitePosition(this.name, this.noradId, this.lat, this.lon, this.altitudeKm);
}

class IssPass {
  final DateTime rise;
  final DateTime set;
  final DateTime peak;
  final double maxElevationDeg;
  final int peakAzimuthDeg;
  const IssPass(this.rise, this.set, this.peak, this.maxElevationDeg, this.peakAzimuthDeg);
}

class OrbitalService {
  OrbitalService._();
  static final OrbitalService instance = OrbitalService._();

  final _elements = <String, Cached<List<dynamic>>>{};

  /// CelesTrak asks for no more than one download per group every two hours.
  Future<List<dynamic>> _elementSets(String group) async {
    final hit = _elements[group];
    if (hit != null && hit.fresherThan(const Duration(hours: 2))) return hit.value;
    final data = await DataGateway.instance.getJson(
      'https://celestrak.org/NORAD/elements/gp.php?GROUP=$group&FORMAT=json',
    );
    if (data is List && data.isNotEmpty) {
      _elements[group] = Cached(data);
      return data;
    }
    return hit?.value ?? const [];
  }

  /// Positions right now. Elements are fetched on-device and sent to the
  /// `orbital` function, which runs SGP4 — CelesTrak rate-limits the shared
  /// cloud IPs the function would otherwise download from.
  Future<({List<SatellitePosition> satellites, IssPass? issPass})> positions({
    String group = 'stations',
    double? passLat,
    double? passLon,
  }) async {
    final elements = await _elementSets(group);
    if (elements.isEmpty) return (satellites: const <SatellitePosition>[], issPass: null);

    final data = await DataGateway.instance.function('orbital', body: {
      'group': group,
      'elements': elements.take(3000).toList(),
      if (passLat != null && passLon != null) 'lat': passLat,
      if (passLat != null && passLon != null) 'lon': passLon,
    });
    if (data is! Map) return (satellites: const <SatellitePosition>[], issPass: null);

    final sats = <SatellitePosition>[
      for (final s in (data['satellites'] as List? ?? const []))
        SatellitePosition(
          (s as List)[0] as String,
          (s[1] as num).toInt(),
          (s[2] as num).toDouble(),
          (s[3] as num).toDouble(),
          (s[4] as num).toDouble(),
        ),
    ];
    final p = data['issPass'] as Map?;
    final pass = p == null
        ? null
        : IssPass(
            DateTime.parse(p['rise'] as String).toLocal(),
            DateTime.parse(p['set'] as String).toLocal(),
            DateTime.parse(p['peak'] as String).toLocal(),
            (p['maxElevationDeg'] as num).toDouble(),
            (p['peakAzimuthDeg'] as num).toInt(),
          );
    return (satellites: sats, issPass: pass);
  }
}

// ── Flight assistant ──────────────────────────────────────────────────────

class AssistantTurn {
  final bool fromUser;
  final String text;
  const AssistantTurn(this.fromUser, this.text);
}

class AssistantReply {
  final String? text;
  final String? error;
  final double? todayUsd;
  final double? capUsd;
  const AssistantReply({this.text, this.error, this.todayUsd, this.capUsd});
}

class AssistantService {
  AssistantService._();
  static final AssistantService instance = AssistantService._();

  Future<AssistantReply> ask(List<AssistantTurn> conversation) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'flight-assistant',
        body: {
          'messages': [
            for (final t in conversation) {'role': t.fromUser ? 'user' : 'assistant', 'content': t.text},
          ],
        },
      ).timeout(const Duration(seconds: 120));
      final data = response.data is String ? jsonDecode(response.data as String) : response.data;
      final usage = (data is Map ? data['usage'] : null) as Map?;
      return AssistantReply(
        text: data is Map ? data['reply'] as String? : null,
        todayUsd: (usage?['todayUsd'] as num?)?.toDouble(),
        capUsd: (usage?['capUsd'] as num?)?.toDouble(),
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      final usage = details is Map ? details['usage'] as Map? : null;
      return AssistantReply(
        error: message ?? 'The assistant is unavailable right now.',
        todayUsd: (usage?['todayUsd'] as num?)?.toDouble(),
        capUsd: (usage?['capUsd'] as num?)?.toDouble(),
      );
    } catch (_) {
      return const AssistantReply(error: 'The assistant is unavailable right now.');
    }
  }
}
