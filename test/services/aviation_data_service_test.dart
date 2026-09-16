import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/services/aviation_data_service.dart';

void main() {
  group('flight number parsing', () {
    // Regression: a greedy 2-3 char designator group used to swallow the first
    // digit, so "AA100" parsed as airline "AA1" and never matched a real
    // airline record.
    test('resolves the correct airline for 3-digit flight numbers', () async {
      final result = await AviationDataService.instance.searchFlight('AA100');
      final flight = result.flights.single;
      expect(flight.airlineIata, 'AA');
      expect(flight.airlineName, 'American Airlines');
    });

    test('resolves airlines with numeric designators', () async {
      final result = await AviationDataService.instance.searchFlight('6E204');
      expect(result.flights.single.airlineIata, '6E');
      expect(result.flights.single.airlineName, 'IndiGo');
    });

    test('resolves 4-digit flight numbers', () async {
      final result = await AviationDataService.instance.searchFlight('BA2490');
      expect(result.flights.single.airlineIata, 'BA');
      expect(result.flights.single.airlineName, 'British Airways');
    });

    test('departs from the operating airline hub', () async {
      final result = await AviationDataService.instance.searchFlight('DL123');
      expect(result.flights.single.departureAirportIata, 'ATL');
    });
  });

  group('OpenSky callsign matching', () {
    // Regression: blank callsigns in the feed satisfied the old substring rule
    // and matched every query, so an unrelated aircraft was reported as live.
    test('never reports a live source for an unknown airline', () async {
      final result = await AviationDataService.instance.searchFlight('ZZ999');
      expect(result.source, isNot('openskynetwork_live'));
      expect(result.source, 'skypulse_aviation_engine');
    });
  });
}
