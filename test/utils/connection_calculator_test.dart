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
  });
}
