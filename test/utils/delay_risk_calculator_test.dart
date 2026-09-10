import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/utils/delay_risk_calculator.dart';
import 'package:skypulse/models/models.dart';

void main() {
  group('DelayRiskCalculator', () {
    test('calculate returns low for on-time flight', () {
      final flight = Flight(
        id: '1',
        tripId: '1',
        flightNumber: '100',
        airlineIata: 'AA',
        departureAirportIata: 'JFK',
        arrivalAirportIata: 'LHR',
        scheduledDeparture: DateTime.now(),
        scheduledArrival: DateTime.now().add(const Duration(hours: 7)),
        status: FlightStatusEnum.active,
      );

      final risk = const DelayRiskCalculator().calculate(
        flight: flight,
      );

      expect(risk.level, DelayRiskLevel.low);
    });

    test('calculate returns high for delayed inbound aircraft', () {
      final flight = Flight(
        id: '1',
        tripId: '1',
        flightNumber: '100',
        airlineIata: 'AA',
        departureAirportIata: 'JFK',
        arrivalAirportIata: 'LHR',
        scheduledDeparture: DateTime.now(),
        scheduledArrival: DateTime.now().add(const Duration(hours: 7)),
        status: FlightStatusEnum.active,
      );

      final inbound = Flight(
        id: '2',
        flightNumber: '99',
        airlineIata: 'AA',
        departureAirportIata: 'ORD',
        arrivalAirportIata: 'JFK',
        scheduledDeparture: DateTime.now().subtract(const Duration(hours: 2)),
        scheduledArrival: DateTime.now().subtract(const Duration(hours: 1)),
        arrivalDelayMinutes: 50,
      );

      final risk = const DelayRiskCalculator().calculate(
        flight: flight,
        inboundAircraftFlight: inbound,
      );

      expect(risk.level, DelayRiskLevel.high);
      expect(risk.factors.any((f) => f.contains('Inbound')), isTrue);
    });
  });
}
