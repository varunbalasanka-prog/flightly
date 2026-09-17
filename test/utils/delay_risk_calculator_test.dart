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
    test('observed thunderstorms raise risk and explain why', () {
      final now = DateTime(2026, 1, 1, 12);
      final flight = Flight(
        id: '1', flightNumber: 'BA178', airlineIata: 'BA',
        departureAirportIata: 'JFK', arrivalAirportIata: 'LHR',
        scheduledDeparture: now.add(const Duration(hours: 2)),
        scheduledArrival: now.add(const Duration(hours: 9)),
      );
      final risk = const DelayRiskCalculator().calculate(
        flight: flight,
        weatherConcerns: const ['Thunderstorms reported at KJFK'],
        now: now,
      );
      expect(risk.level, DelayRiskLevel.medium);
      expect(risk.factors, contains('Thunderstorms reported at KJFK'));
    });

    test('an operating aircraft still far away an hour out is high risk', () {
      final now = DateTime(2026, 1, 1, 12);
      final flight = Flight(
        id: '1', flightNumber: 'BA178', airlineIata: 'BA',
        departureAirportIata: 'JFK', arrivalAirportIata: 'LHR',
        scheduledDeparture: now.add(const Duration(minutes: 60)),
        scheduledArrival: now.add(const Duration(hours: 8)),
      );
      final risk = const DelayRiskCalculator().calculate(
        flight: flight,
        inboundPosition: const InboundAircraftPosition(airborne: true, distanceToDepartureKm: 2400),
        now: now,
      );
      expect(risk.level, DelayRiskLevel.high);
      expect(risk.factors.first, contains('2400 km away'));
    });

    test('ignores aircraft position when the schedule is not known', () {
      final now = DateTime(2026, 1, 1, 12);
      final flight = Flight(
        id: '1', flightNumber: 'BA178', airlineIata: 'BA',
        departureAirportIata: 'JFK', arrivalAirportIata: 'LHR',
        scheduledDeparture: now.add(const Duration(minutes: 60)),
        scheduledArrival: now.add(const Duration(hours: 8)),
        scheduleIsKnown: false,
      );
      final risk = const DelayRiskCalculator().calculate(
        flight: flight,
        inboundPosition: const InboundAircraftPosition(airborne: true, distanceToDepartureKm: 2400),
        now: now,
      );
      expect(risk.factors.join(' '), isNot(contains('km away')));
    });
  });
}
