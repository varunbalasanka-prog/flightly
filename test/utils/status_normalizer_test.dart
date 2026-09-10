import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/models/models.dart';
import 'package:skypulse/utils/status_normalizer.dart';

void main() {
  group('StatusNormalizer', () {
    const normalizer = StatusNormalizer();

    test('normalize maps known statuses correctly', () {
      expect(normalizer.normalize('scheduled'), FlightStatusEnum.scheduled);
      expect(normalizer.normalize('active'), FlightStatusEnum.active);
      expect(normalizer.normalize('en-route'), FlightStatusEnum.active);
      expect(normalizer.normalize('en_route'), FlightStatusEnum.active);
      expect(normalizer.normalize('landed'), FlightStatusEnum.landed);
      expect(normalizer.normalize('cancelled'), FlightStatusEnum.cancelled);
      expect(normalizer.normalize('diverted'), FlightStatusEnum.diverted);
      expect(normalizer.normalize('incident'), FlightStatusEnum.incident);
    });

    test('normalize handles case and whitespace', () {
      expect(normalizer.normalize('   ACTIVE  '), FlightStatusEnum.active);
      expect(normalizer.normalize('Landed'), FlightStatusEnum.landed);
    });

    test('normalize returns unknown for unrecognized or null', () {
      expect(normalizer.normalize(null), FlightStatusEnum.unknown);
      expect(normalizer.normalize(''), FlightStatusEnum.unknown);
      expect(normalizer.normalize('delayed'), FlightStatusEnum.unknown);
    });

    test('fromAviationstackResponse parses correctly', () {
      final rawResponse = {
        'flight_date': '2023-12-01',
        'flight_status': 'active',
        'departure': {
          'airport': 'San Francisco International',
          'iata': 'SFO',
          'scheduled': '2023-12-01T10:00:00+00:00',
          'delay': 15,
        },
        'arrival': {
          'airport': 'John F Kennedy International',
          'iata': 'JFK',
          'scheduled': '2023-12-01T18:30:00+00:00',
        },
        'airline': {
          'name': 'American Airlines',
          'iata': 'AA',
        },
        'flight': {
          'number': '123',
          'iata': 'AA123',
        },
      };

      final flight = normalizer.fromAviationstackResponse(rawResponse);
      
      expect(flight, isNotNull);
      expect(flight!.flightNumber, 'AA123');
      expect(flight.departureAirportIata, 'SFO');
      expect(flight.arrivalAirportIata, 'JFK');
      expect(flight.departureDelayMinutes, 15);
      expect(flight.status, FlightStatusEnum.active);
    });

    test('fromAviationstackResponse returns null for missing critical data', () {
      final rawResponse = {
        'flight_status': 'active',
        // Missing departure, arrival, flight nodes entirely
      };

      final flight = normalizer.fromAviationstackResponse(rawResponse);
      expect(flight, isNull);
    });
  });
}
