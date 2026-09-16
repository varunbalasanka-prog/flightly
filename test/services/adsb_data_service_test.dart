import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/services/adsb_data_service.dart';

/// These hit the real public APIs. They assert on facts that do not change
/// (AA100 is JFK->LHR), not on live traffic, so they stay deterministic.
void main() {
  final adsb = AdsbDataService.instance;

  setUp(adsb.clearCaches);

  group('route lookup', () {
    test('resolves a real route from an IATA flight number', () async {
      final route = await adsb.lookupRoute('AA100');
      expect(route, isNotNull);
      expect(route!.airlineName, 'American Airlines');
      expect(route.origin.iataCode, 'JFK');
      expect(route.destination.iataCode, 'LHR');
      expect(route.destination.name, contains('Heathrow'));
      // Real coordinates, not a lookup table of 19 airports.
      expect(route.origin.latitude, closeTo(40.64, 0.1));
      expect(route.origin.longitude, closeTo(-73.78, 0.1));
    });

    test('returns both callsign forms, removing the need for a local table',
        () async {
      final route = await adsb.lookupRoute('AA100');
      expect(route!.callsignIata, 'AA100');
      expect(route.callsignIcao, 'AAL100');
    });

    test('accepts the ICAO form too', () async {
      final route = await adsb.lookupRoute('BAW178');
      expect(route!.origin.iataCode, 'JFK');
      expect(route.destination.iataCode, 'LHR');
    });

    test('normalises spacing and case', () async {
      final route = await adsb.lookupRoute('  ba 178 ');
      expect(route, isNotNull);
      expect(route!.airlineIata, 'BA');
    });

    test('returns null for an unknown callsign rather than inventing one',
        () async {
      expect(await adsb.lookupRoute('ZZ9999'), isNull);
    });

    test('caches, so a repeat lookup does not re-hit the API', () async {
      final first = await adsb.lookupRoute('AA100');
      final second = await adsb.lookupRoute('AA100');
      expect(identical(first, second), isTrue);
    });
  });

  group('aircraft registry', () {
    test('resolves a Mode-S hex to a real airframe', () async {
      final aircraft = await adsb.lookupAircraft('A835AF');
      expect(aircraft, isNotNull);
      expect(aircraft!.registration, 'N628TS');
      expect(aircraft.manufacturer, contains('Gulfstream'));
    });
  });

  group('live traffic', () {
    test('a radius query returns a bounded, plausible set', () async {
      // Around Heathrow. Traffic varies, so assert on shape, not on count.
      final traffic = await adsb.lookupTrafficNear(51.47, -0.46, radiusNm: 60);
      for (final aircraft in traffic) {
        expect(aircraft.modeSHex, isNotEmpty);
        expect(aircraft.latitude, inInclusiveRange(49.0, 54.0));
        expect(aircraft.longitude, inInclusiveRange(-4.0, 3.0));
      }
    });
  });
}
