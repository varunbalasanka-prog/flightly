import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Real, key-free flight data.
///
/// Two public sources, both free and neither requiring an API key:
///
/// * **adsbdb.com** — resolves a flight number to its actual route (airline,
///   origin and destination airports with coordinates) and a Mode-S hex code
///   to a real aircraft (registration, type, operator). Static reference data,
///   so it is cached aggressively.
/// * **adsb.lol** — live ADS-B transponder positions, queryable by callsign or
///   by geographic radius.
///
/// This replaces `AviationDataService`, which invented routes, gates, baggage
/// belts and tail numbers from a hash of the flight number. Fields these
/// sources genuinely do not carry — scheduled times, gates, terminals, baggage
/// belts, delay minutes — are left null rather than filled with plausible
/// fiction.
///
/// Source discovery credit: the endpoint choices and the 24h negative-caching
/// approach follow God's Eye View by Bilawal Sidhu (MIT licensed),
/// https://github.com/bilawalsidhu/gods-eye-view
class AdsbDataService {
  static final AdsbDataService instance = AdsbDataService._();
  AdsbDataService._() : _injectedClient = null;

  @visibleForTesting
  AdsbDataService.forTesting({http.Client? client}) : _injectedClient = client;

  final http.Client? _injectedClient;
  http.Client get _client => _injectedClient ?? _shared;
  static final http.Client _shared = http.Client();

  static const _routeBase = 'https://api.adsbdb.com/v0/callsign';
  static const _aircraftBase = 'https://api.adsbdb.com/v0/aircraft';
  static const _liveBase = 'https://api.adsb.lol/v2';

  /// Route and aircraft records are effectively static, so cache them for a day.
  /// Misses are cached too: an unknown callsign stays unknown, and re-asking on
  /// every keystroke would be rude to a free service.
  static const _referenceTtl = Duration(hours: 24);

  /// Positions go stale in seconds, so this is only a burst guard.
  static const _positionTtl = Duration(seconds: 20);

  static const _timeout = Duration(seconds: 8);

  /// adsb.lol sends no Access-Control-Allow-Origin header, so a browser blocks
  /// it. On web we go through the live-position Edge Function instead; native
  /// builds have no CORS and call the API directly. (adsbdb does send CORS.)
  static const _useProxyForLive = kIsWeb;

  /// After repeated failures, stop retrying for a while. Without this the map's
  /// refresh timer hammered a blocked endpoint every 20 seconds indefinitely.
  static const _failureThreshold = 3;
  static const _backoff = Duration(minutes: 5);
  int _liveFailures = 0;
  DateTime? _liveBackoffUntil;

  final _routeCache = <String, _CacheEntry<FlightRoute?>>{};
  final _aircraftCache = <String, _CacheEntry<AircraftRecord?>>{};
  final _positionCache = <String, _CacheEntry<LivePosition?>>{};

  @visibleForTesting
  void clearCaches() {
    _routeCache.clear();
    _aircraftCache.clear();
    _positionCache.clear();
  }

  /// Resolves a flight number to its real route.
  ///
  /// Accepts either form — adsbdb understands IATA (`AA100`) and ICAO
  /// (`AAL100`) callsigns and returns both, so no local airline table is
  /// needed. Returns null when the callsign is unknown to the database, which
  /// is common for regional and charter flights.
  Future<FlightRoute?> lookupRoute(String flightNumber) async {
    final callsign = _normalizeCallsign(flightNumber);
    if (callsign.isEmpty) return null;

    final cached = _routeCache[callsign];
    if (cached != null && cached.isFresh(_referenceTtl)) return cached.value;

    final body = await _getJson('$_routeBase/$callsign');
    // A transport failure is not the same as "no such route": don't poison the
    // cache with a miss we are not sure about.
    if (body == null) return cached?.value;

    final route = FlightRoute._tryParse(body);
    _routeCache[callsign] = _CacheEntry(route);
    return route;
  }

  /// Resolves a Mode-S hex code to a real airframe.
  Future<AircraftRecord?> lookupAircraft(String modeSHex) async {
    final hex = modeSHex.trim().toUpperCase();
    if (hex.isEmpty) return null;

    final cached = _aircraftCache[hex];
    if (cached != null && cached.isFresh(_referenceTtl)) return cached.value;

    final body = await _getJson('$_aircraftBase/$hex');
    if (body == null) return cached?.value;

    final aircraft = AircraftRecord._tryParse(body);
    _aircraftCache[hex] = _CacheEntry(aircraft);
    return aircraft;
  }

  /// Current transponder position for a callsign, or null when the aircraft is
  /// not airborne (or is outside the network's coverage).
  ///
  /// Both forms are tried: aircraft transmit the ICAO callsign, but users type
  /// the IATA flight number.
  Future<LivePosition?> lookupLivePosition(
    String flightNumber, {
    String? icaoCallsign,
  }) async {
    final candidates = <String>{
      if (icaoCallsign != null) _normalizeCallsign(icaoCallsign),
      _normalizeCallsign(flightNumber),
    }..removeWhere((c) => c.isEmpty);

    for (final callsign in candidates) {
      final cached = _positionCache[callsign];
      if (cached != null && cached.isFresh(_positionTtl)) {
        if (cached.value != null) return cached.value;
        continue;
      }

      final body = await _fetchLive(callsign);
      if (body == null) continue;

      final position = LivePosition._tryParseFirst(body);
      _positionCache[callsign] = _CacheEntry(position);
      if (position != null) return position;
    }
    return null;
  }

  /// Fetches a live fix, honouring the backoff and the web proxy.
  Future<Map<String, dynamic>?> _fetchLive(String callsign) async {
    final until = _liveBackoffUntil;
    if (until != null && DateTime.now().isBefore(until)) return null;

    final body = _useProxyForLive
        ? await _getJsonViaProxy(callsign)
        : await _getJson('$_liveBase/callsign/$callsign');

    if (body == null) {
      if (++_liveFailures >= _failureThreshold) {
        _liveBackoffUntil = DateTime.now().add(_backoff);
        _liveFailures = 0;
        debugPrint(
          'Live position lookups failing; pausing for ${_backoff.inMinutes}min.',
        );
      }
      return null;
    }

    _liveFailures = 0;
    _liveBackoffUntil = null;
    return body;
  }

  /// Calls the live-position Edge Function, which adds the CORS headers
  /// adsb.lol omits and shares one upstream request across clients.
  Future<Map<String, dynamic>?> _getJsonViaProxy(String callsign) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke('live-position', body: {'callsign': callsign})
          .timeout(_timeout);

      if (response.status != 200) return null;
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is String) {
        final decoded = jsonDecode(data);
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      return null;
    } catch (e) {
      debugPrint('live-position proxy failed: $e');
      return null;
    }
  }

  /// Live traffic within [radiusNm] nautical miles of a point.
  ///
  /// This is the replacement for OpenSky's `/states/all`, which returns the
  /// entire global picture — roughly 850 KB and well over 30 s — for every
  /// single query. A 50 nm radius is about 12 KB and under two seconds.
  Future<List<LivePosition>> lookupTrafficNear(
    double latitude,
    double longitude, {
    int radiusNm = 50,
  }) async {
    final radius = radiusNm.clamp(1, 250);
    final body = await _getJson(
      '$_liveBase/lat/${latitude.toStringAsFixed(4)}'
      '/lon/${longitude.toStringAsFixed(4)}/dist/$radius',
    );
    if (body == null) return const [];

    final list = body['ac'];
    if (list is! List) return const [];

    return list
        .whereType<Map<String, dynamic>>()
        .map(LivePosition._tryParse)
        .whereType<LivePosition>()
        .toList(growable: false);
  }

  /// Uppercase, stripped of spaces and hyphens. `"ba 178"` -> `"BA178"`.
  static String _normalizeCallsign(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '').trim();

  /// Returns the decoded body, or null on any transport/parse failure.
  /// A 404 is a real answer ("not in the database") and returns an empty map so
  /// callers can distinguish it from a network error.
  Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);

      if (response.statusCode == 404) return const <String, dynamic>{};
      if (response.statusCode != 200) {
        debugPrint('ADS-B lookup ${response.statusCode} for $url');
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('ADS-B lookup failed for $url: $e');
      return null;
    }
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime at;
  _CacheEntry(this.value) : at = DateTime.now();

  bool isFresh(Duration ttl) => DateTime.now().difference(at) < ttl;
}

/// An airport as reported by adsbdb.
class RouteAirport {
  final String iataCode;
  final String icaoCode;
  final String name;
  final String municipality;
  final String countryName;
  final double latitude;
  final double longitude;

  const RouteAirport({
    required this.iataCode,
    required this.icaoCode,
    required this.name,
    required this.municipality,
    required this.countryName,
    required this.latitude,
    required this.longitude,
  });

  static RouteAirport? _tryParse(Object? raw) {
    if (raw is! Map) return null;
    final iata = raw['iata_code'] as String?;
    final lat = (raw['latitude'] as num?)?.toDouble();
    final lon = (raw['longitude'] as num?)?.toDouble();
    if (iata == null || iata.isEmpty || lat == null || lon == null) return null;

    return RouteAirport(
      iataCode: iata,
      icaoCode: raw['icao_code'] as String? ?? '',
      name: raw['name'] as String? ?? iata,
      municipality: raw['municipality'] as String? ?? '',
      countryName: raw['country_name'] as String? ?? '',
      latitude: lat,
      longitude: lon,
    );
  }
}

/// A real scheduled route. Carries no times — adsbdb maps callsigns to
/// city pairs, not to timetables.
class FlightRoute {
  final String callsignIata;
  final String callsignIcao;
  final String airlineName;
  final String airlineIata;
  final String airlineIcao;
  final RouteAirport origin;
  final RouteAirport destination;

  const FlightRoute({
    required this.callsignIata,
    required this.callsignIcao,
    required this.airlineName,
    required this.airlineIata,
    required this.airlineIcao,
    required this.origin,
    required this.destination,
  });

  static FlightRoute? _tryParse(Map<String, dynamic> body) {
    final route = (body['response'] as Map?)?['flightroute'];
    if (route is! Map) return null;

    final origin = RouteAirport._tryParse(route['origin']);
    final destination = RouteAirport._tryParse(route['destination']);
    if (origin == null || destination == null) return null;

    final airline = route['airline'] as Map?;
    return FlightRoute(
      callsignIata: route['callsign_iata'] as String? ?? '',
      callsignIcao: route['callsign_icao'] as String? ?? '',
      airlineName: airline?['name'] as String? ?? '',
      airlineIata: airline?['iata'] as String? ?? '',
      airlineIcao: airline?['icao'] as String? ?? '',
      origin: origin,
      destination: destination,
    );
  }
}

/// A real airframe from the adsbdb registry.
class AircraftRecord {
  final String registration;
  final String type;
  final String icaoType;
  final String manufacturer;
  final String registeredOwner;
  final String modeSHex;
  final String? photoUrl;
  final String? photoThumbnailUrl;

  const AircraftRecord({
    required this.registration,
    required this.type,
    required this.icaoType,
    required this.manufacturer,
    required this.registeredOwner,
    required this.modeSHex,
    this.photoUrl,
    this.photoThumbnailUrl,
  });

  static AircraftRecord? _tryParse(Map<String, dynamic> body) {
    final aircraft = (body['response'] as Map?)?['aircraft'];
    if (aircraft is! Map) return null;

    final registration = aircraft['registration'] as String?;
    if (registration == null || registration.isEmpty) return null;

    return AircraftRecord(
      registration: registration,
      type: aircraft['type'] as String? ?? '',
      icaoType: aircraft['icao_type'] as String? ?? '',
      manufacturer: aircraft['manufacturer'] as String? ?? '',
      registeredOwner: aircraft['registered_owner'] as String? ?? '',
      modeSHex: aircraft['mode_s'] as String? ?? '',
      photoUrl: aircraft['url_photo'] as String?,
      photoThumbnailUrl: aircraft['url_photo_thumbnail'] as String?,
    );
  }
}

/// A live transponder fix. Every value here was actually broadcast by the
/// aircraft — nothing is interpolated.
class LivePosition {
  final String modeSHex;
  final String callsign;
  final double latitude;
  final double longitude;

  /// Barometric altitude in feet. Null while on the ground.
  final double? altitudeFeet;

  /// Ground speed in knots.
  final double? groundSpeedKnots;

  /// True track in degrees.
  final double? headingDegrees;

  /// Vertical rate in feet per minute. Positive is climbing.
  final double? verticalRateFpm;

  final bool onGround;

  /// Registration and type, when the feed carries them.
  final String? registration;
  final String? aircraftType;

  /// Seconds since this aircraft was last seen.
  final double? secondsSinceSeen;

  final DateTime observedAt;

  const LivePosition({
    required this.modeSHex,
    required this.callsign,
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    this.altitudeFeet,
    this.groundSpeedKnots,
    this.headingDegrees,
    this.verticalRateFpm,
    this.onGround = false,
    this.registration,
    this.aircraftType,
    this.secondsSinceSeen,
  });

  static LivePosition? _tryParseFirst(Map<String, dynamic> body) {
    final list = body['ac'];
    if (list is! List) return null;
    for (final entry in list) {
      if (entry is Map<String, dynamic>) {
        final parsed = _tryParse(entry);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static LivePosition? _tryParse(Map<String, dynamic> raw) {
    final hex = (raw['hex'] as String?)?.trim();
    final lat = (raw['lat'] as num?)?.toDouble();
    final lon = (raw['lon'] as num?)?.toDouble();
    if (hex == null || hex.isEmpty || lat == null || lon == null) return null;

    // `alt_baro` is the string "ground" when the aircraft is not airborne.
    final rawAltitude = raw['alt_baro'];
    final onGround = rawAltitude == 'ground';

    return LivePosition(
      modeSHex: hex.toUpperCase(),
      callsign: (raw['flight'] as String?)?.trim() ?? '',
      latitude: lat,
      longitude: lon,
      altitudeFeet: onGround ? null : (rawAltitude as num?)?.toDouble(),
      groundSpeedKnots: (raw['gs'] as num?)?.toDouble(),
      headingDegrees: (raw['track'] as num?)?.toDouble(),
      verticalRateFpm: (raw['baro_rate'] as num?)?.toDouble() ??
          (raw['geom_rate'] as num?)?.toDouble(),
      onGround: onGround,
      registration: (raw['r'] as String?)?.trim(),
      aircraftType: (raw['t'] as String?)?.trim(),
      secondsSinceSeen: (raw['seen'] as num?)?.toDouble(),
      observedAt: DateTime.now(),
    );
  }
}
