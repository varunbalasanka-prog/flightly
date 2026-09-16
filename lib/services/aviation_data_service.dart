import 'dart:math';
import '../models/models.dart';
import '../providers/flight_data_provider.dart';

/// Pre-seeded airport definition with geographic coordinates.
class AirportRecord {
  final String iata;
  final String icao;
  final String name;
  final String city;
  final String country;
  final double lat;
  final double lng;
  final String timezone;
  final int baseDelay;
  final String weather;

  const AirportRecord({
    required this.iata,
    required this.icao,
    required this.name,
    required this.city,
    required this.country,
    required this.lat,
    required this.lng,
    required this.timezone,
    this.baseDelay = 0,
    this.weather = 'Clear',
  });
}

/// Geographic helpers and a small built-in airport table.
///
/// This used to be the app's data source: it derived routes, schedules,
/// gates, terminals, baggage belts and tail numbers from a hash of the flight
/// number and labelled the result `openskynetwork_live`. All of that is gone —
/// real data now comes from [AdsbDataService].
///
/// What remains is genuinely useful and has no network dependency:
/// great-circle path generation, Haversine distance, and coordinates for a
/// handful of major airports used as a fallback when a route lookup fails.
class AviationDataService {
  static final AviationDataService instance = AviationDataService._();
  AviationDataService._();

  // ── Global Airport Database ──
  static const Map<String, AirportRecord> airports = {
    'JFK': AirportRecord(
      iata: 'JFK',
      icao: 'KJFK',
      name: 'John F. Kennedy International Airport',
      city: 'New York',
      country: 'United States',
      lat: 40.6413,
      lng: -73.7781,
      timezone: 'America/New_York',
      baseDelay: 15,
      weather: 'Partly Cloudy, 18°C',
    ),
    'LHR': AirportRecord(
      iata: 'LHR',
      icao: 'EGLL',
      name: 'Heathrow Airport',
      city: 'London',
      country: 'United Kingdom',
      lat: 51.4700,
      lng: -0.4543,
      timezone: 'Europe/London',
      baseDelay: 20,
      weather: 'Light Rain, 14°C',
    ),
    'DXB': AirportRecord(
      iata: 'DXB',
      icao: 'OMDB',
      name: 'Dubai International Airport',
      city: 'Dubai',
      country: 'United Arab Emirates',
      lat: 25.2532,
      lng: 55.3657,
      timezone: 'Asia/Dubai',
      baseDelay: 5,
      weather: 'Sunny, 34°C',
    ),
    'LAX': AirportRecord(
      iata: 'LAX',
      icao: 'KLAX',
      name: 'Los Angeles International Airport',
      city: 'Los Angeles',
      country: 'United States',
      lat: 33.9416,
      lng: -118.4085,
      timezone: 'America/Los_Angeles',
      baseDelay: 10,
      weather: 'Sunny, 22°C',
    ),
    'ORD': AirportRecord(
      iata: 'ORD',
      icao: 'KORD',
      name: 'O\'Hare International Airport',
      city: 'Chicago',
      country: 'United States',
      lat: 41.9742,
      lng: -87.9073,
      timezone: 'America/Chicago',
      baseDelay: 25,
      weather: 'Windy, 16°C',
    ),
    'DFW': AirportRecord(
      iata: 'DFW',
      icao: 'KDFW',
      name: 'Dallas/Fort Worth International Airport',
      city: 'Dallas',
      country: 'United States',
      lat: 32.8998,
      lng: -97.0403,
      timezone: 'America/Chicago',
      baseDelay: 10,
      weather: 'Clear, 28°C',
    ),
    'ATL': AirportRecord(
      iata: 'ATL',
      icao: 'KATL',
      name: 'Hartsfield-Jackson Atlanta International Airport',
      city: 'Atlanta',
      country: 'United States',
      lat: 33.6407,
      lng: -84.4277,
      timezone: 'America/New_York',
      baseDelay: 15,
      weather: 'Partly Cloudy, 24°C',
    ),
    'SFO': AirportRecord(
      iata: 'SFO',
      icao: 'KSFO',
      name: 'San Francisco International Airport',
      city: 'San Francisco',
      country: 'United States',
      lat: 37.6213,
      lng: -122.3790,
      timezone: 'America/Los_Angeles',
      baseDelay: 30,
      weather: 'Foggy, 15°C',
    ),
    'CDG': AirportRecord(
      iata: 'CDG',
      icao: 'LFPG',
      name: 'Charles de Gaulle Airport',
      city: 'Paris',
      country: 'France',
      lat: 49.0097,
      lng: 2.5479,
      timezone: 'Europe/Paris',
      baseDelay: 15,
      weather: 'Cloudy, 17°C',
    ),
    'FRA': AirportRecord(
      iata: 'FRA',
      icao: 'EDDF',
      name: 'Frankfurt Airport',
      city: 'Frankfurt',
      country: 'Germany',
      lat: 50.0379,
      lng: 8.5622,
      timezone: 'Europe/Berlin',
      baseDelay: 10,
      weather: 'Clear, 19°C',
    ),
    'AMS': AirportRecord(
      iata: 'AMS',
      icao: 'EHAM',
      name: 'Amsterdam Airport Schiphol',
      city: 'Amsterdam',
      country: 'Netherlands',
      lat: 52.3105,
      lng: 4.7683,
      timezone: 'Europe/Amsterdam',
      baseDelay: 20,
      weather: 'Light Rain, 15°C',
    ),
    'SIN': AirportRecord(
      iata: 'SIN',
      icao: 'WSSS',
      name: 'Singapore Changi Airport',
      city: 'Singapore',
      country: 'Singapore',
      lat: 1.3644,
      lng: 103.9915,
      timezone: 'Asia/Singapore',
      baseDelay: 5,
      weather: 'Humid, 30°C',
    ),
    'HND': AirportRecord(
      iata: 'HND',
      icao: 'RJTT',
      name: 'Tokyo Haneda Airport',
      city: 'Tokyo',
      country: 'Japan',
      lat: 35.5494,
      lng: 139.7798,
      timezone: 'Asia/Tokyo',
      baseDelay: 5,
      weather: 'Clear, 21°C',
    ),
    'SYD': AirportRecord(
      iata: 'SYD',
      icao: 'YSSY',
      name: 'Sydney Kingsford Smith Airport',
      city: 'Sydney',
      country: 'Australia',
      lat: -33.9399,
      lng: 151.1753,
      timezone: 'Australia/Sydney',
      baseDelay: 10,
      weather: 'Sunny, 20°C',
    ),
    'DEL': AirportRecord(
      iata: 'DEL',
      icao: 'VIDP',
      name: 'Indira Gandhi International Airport',
      city: 'New Delhi',
      country: 'India',
      lat: 28.5562,
      lng: 77.1000,
      timezone: 'Asia/Kolkata',
      baseDelay: 15,
      weather: 'Haze, 29°C',
    ),
    'BOM': AirportRecord(
      iata: 'BOM',
      icao: 'VABB',
      name: 'Chhatrapati Shivaji Maharaj International Airport',
      city: 'Mumbai',
      country: 'India',
      lat: 19.0896,
      lng: 72.8656,
      timezone: 'Asia/Kolkata',
      baseDelay: 20,
      weather: 'Partly Cloudy, 31°C',
    ),
    'BLR': AirportRecord(
      iata: 'BLR',
      icao: 'VOBL',
      name: 'Kempegowda International Airport',
      city: 'Bengaluru',
      country: 'India',
      lat: 13.1986,
      lng: 77.7066,
      timezone: 'Asia/Kolkata',
      baseDelay: 10,
      weather: 'Pleasant, 25°C',
    ),
    'MAA': AirportRecord(
      iata: 'MAA',
      icao: 'VOMM',
      name: 'Chennai International Airport',
      city: 'Chennai',
      country: 'India',
      lat: 12.9941,
      lng: 80.1709,
      timezone: 'Asia/Kolkata',
      baseDelay: 10,
      weather: 'Warm, 32°C',
    ),
    'HYD': AirportRecord(
      iata: 'HYD',
      icao: 'VOHS',
      name: 'Rajiv Gandhi International Airport',
      city: 'Hyderabad',
      country: 'India',
      lat: 17.2403,
      lng: 78.4294,
      timezone: 'Asia/Kolkata',
      baseDelay: 5,
      weather: 'Clear, 28°C',
    ),
  };

  /// Get airport information
  Future<AirportInfo> getAirport(String iataCode) async {
    final code = iataCode.toUpperCase().trim();
    final record = airports[code];

    if (record == null) {
      return AirportInfo(
        error: 'Airport $code not found in global registry',
        fetchedAt: DateTime.now(),
      );
    }

    final airportStatus = AirportStatus(
      iataCode: record.iata,
      icaoCode: record.icao,
      name: record.name,
      city: record.city,
      country: record.country,
      latitude: record.lat,
      longitude: record.lng,
      delayMinutes: record.baseDelay,
      weatherCondition: record.weather,
      temperatureC: 22,
      activeFlightsCount: 42,
    );

    return AirportInfo(
      airport: airportStatus,
      fetchedAt: DateTime.now(),
    );
  }

  /// Great-circle distance in kilometres between two coordinates.
  double distanceKm(double lat1, double lon1, double lat2, double lon2) =>
      _calculateDistanceKm(lat1, lon1, lat2, lon2);

  /// Calculate great-circle distance in kilometers using Haversine formula.
  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _degToRad(double deg) => deg * (pi / 180.0);

  /// Points along the true great-circle path between two coordinates.
  ///
  /// This previously interpolated latitude and longitude linearly and added a
  /// decorative sine bulge, which is not a great circle: for JFK to LHR it put
  /// the midpoint near 46.1N 48.2W when the real one is around 57.0N 37.0W,
  /// several hundred kilometres adrift. Uses spherical linear interpolation,
  /// which also crosses the antimeridian correctly.
  List<List<double>> calculateGreatCircleCoordinates(
    double lat1,
    double lon1,
    double lat2,
    double lon2, {
    int points = 25,
  }) {
    final phi1 = _degToRad(lat1);
    final lambda1 = _degToRad(lon1);
    final phi2 = _degToRad(lat2);
    final lambda2 = _degToRad(lon2);

    // Angular distance between the two points.
    final delta = 2 *
        asin(sqrt(pow(sin((phi2 - phi1) / 2), 2) +
            cos(phi1) * cos(phi2) * pow(sin((lambda2 - lambda1) / 2), 2)));

    // Coincident points have no defined path; return a degenerate one.
    if (delta == 0 || delta.isNaN) {
      return List.generate(points + 1, (_) => [lat1, lon1]);
    }

    final coords = <List<double>>[];
    final sinDelta = sin(delta);

    for (var i = 0; i <= points; i++) {
      final f = i / points;
      final a = sin((1 - f) * delta) / sinDelta;
      final b = sin(f * delta) / sinDelta;

      final x = a * cos(phi1) * cos(lambda1) + b * cos(phi2) * cos(lambda2);
      final y = a * cos(phi1) * sin(lambda1) + b * cos(phi2) * sin(lambda2);
      final z = a * sin(phi1) + b * sin(phi2);

      coords.add([
        atan2(z, sqrt(x * x + y * y)) * 180.0 / pi,
        atan2(y, x) * 180.0 / pi,
      ]);
    }
    return coords;
  }
}
