import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/utils/connection_calculator.dart';
import 'package:skypulse/models/models.dart';

void main() {
  group('ConnectionCalculator', () {
    test('calculate returns safe for 2 hour connection', () {
      final flight1 = Flight(
        id: '1',
        tripId: '1',
        flightNumber: '100',
        airlineIata: 'AA',
        departureAirportIata: 'JFK',
        arrivalAirportIata: 'LHR',
        scheduledDeparture: DateTime.now(),
        scheduledArrival: DateTime.now(),
        status: FlightStatusEnum.active,
      );

      final flight2 = Flight(
        id: '2',
        tripId: '1',
        flightNumber: '200',
        airlineIata: 'AA',
        departureAirportIata: 'LHR',
        arrivalAirportIata: 'CDG',
        scheduledDeparture: DateTime.now().add(const Duration(hours: 2)),
        scheduledArrival: DateTime.now().add(const Duration(hours: 3)),
        status: FlightStatusEnum.scheduled,
      );

      final connection = const ConnectionCalculator().calculate(inboundFlight: flight1, outboundFlight: flight2);

      expect(connection.status, ConnectionStatusEnum.safe);
      expect(connection.connectionMinutes, 120);
    });

    test('calculate returns missed for 30 min connection (under tight threshold)', () {
      final flight1 = Flight(
        id: '1',
        tripId: '1',
        flightNumber: '100',
        airlineIata: 'AA',
        departureAirportIata: 'JFK',
        arrivalAirportIata: 'LHR',
        scheduledDeparture: DateTime.now(),
        scheduledArrival: DateTime.now(),
        status: FlightStatusEnum.active,
      );

      final flight2 = Flight(
        id: '2',
        tripId: '1',
        flightNumber: '200',
        airlineIata: 'AA',
        departureAirportIata: 'LHR',
        arrivalAirportIata: 'CDG',
        scheduledDeparture: DateTime.now().add(const Duration(minutes: 30)),
        scheduledArrival: DateTime.now().add(const Duration(hours: 2)),
        status: FlightStatusEnum.scheduled,
      );

      final connection = const ConnectionCalculator().calculate(inboundFlight: flight1, outboundFlight: flight2);

      // Connection is 30 mins, tight is 45, so it should be atRisk
      expect(connection.status, ConnectionStatusEnum.atRisk);
      expect(connection.connectionMinutes, 30);
    });

    // Regression: `bestArrivalTime` already prefers the estimated arrival,
    // which carries the delay. Subtracting arrivalDelayMinutes on top of that
    // double-counted it and downgraded comfortable connections.
    test('does not subtract a delay already baked into the arrival time', () {
      final base = DateTime(2026, 1, 1, 12);
      final inbound = Flight(
        id: '1',
        flightNumber: 'AA1',
        airlineIata: 'AA',
        departureAirportIata: 'JFK',
        arrivalAirportIata: 'LHR',
        scheduledDeparture: base.subtract(const Duration(hours: 6)),
        scheduledArrival: base,
        estimatedArrival: base.add(const Duration(minutes: 30)),
        arrivalDelayMinutes: 30,
        status: FlightStatusEnum.active,
      );
      final outbound = Flight(
        id: '2',
        flightNumber: 'AA2',
        airlineIata: 'AA',
        departureAirportIata: 'LHR',
        arrivalAirportIata: 'CDG',
        scheduledDeparture: base.add(const Duration(minutes: 90)),
        scheduledArrival: base.add(const Duration(hours: 3)),
        status: FlightStatusEnum.scheduled,
      );

      final connection = const ConnectionCalculator()
          .calculate(inboundFlight: inbound, outboundFlight: outbound);

      // Outbound 13:30 minus real arrival 12:30 == 60min, which is comfortable.
      expect(connection.connectionMinutes, 60);
      expect(connection.status, ConnectionStatusEnum.safe);
      expect(connection.explanation, isNot(contains('effective connection')));
    });

    // The adjustment is still right when only a scheduled time is available.
    test('applies the delay when the arrival time does not include it', () {
      final base = DateTime(2026, 1, 1, 12);
      final inbound = Flight(
        id: '1',
        flightNumber: 'AA1',
        airlineIata: 'AA',
        departureAirportIata: 'JFK',
        arrivalAirportIata: 'LHR',
        scheduledDeparture: base.subtract(const Duration(hours: 6)),
        scheduledArrival: base,
        arrivalDelayMinutes: 40,
        status: FlightStatusEnum.active,
      );
      final outbound = Flight(
        id: '2',
        flightNumber: 'AA2',
        airlineIata: 'AA',
        departureAirportIata: 'LHR',
        arrivalAirportIata: 'CDG',
        scheduledDeparture: base.add(const Duration(minutes: 75)),
        scheduledArrival: base.add(const Duration(hours: 3)),
        status: FlightStatusEnum.scheduled,
      );

      final connection = const ConnectionCalculator()
          .calculate(inboundFlight: inbound, outboundFlight: outbound);

      expect(connection.connectionMinutes, 75);
      expect(connection.status, ConnectionStatusEnum.atRisk);
      expect(connection.explanation, contains('35min'));
    });
  });
}
