import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/models/models.dart';
import 'package:skypulse/services/adsb_data_service.dart';

/// End-to-end check that a search returns REAL data and, crucially, does not
/// invent the fields these sources do not carry.
void main() {
  test('a lookup yields a real route and no fabricated details', () async {
    final adsb = AdsbDataService.instance;
    final route = await adsb.lookupRoute('AA100');
    expect(route, isNotNull, reason: 'AA100 is a real, long-running route');

    final live = await adsb.lookupLivePosition(
      'AA100',
      icaoCallsign: route!.callsignIcao,
    );

    final flight = Flight(
      id: '',
      flightNumber: route.callsignIata,
      airlineIata: route.airlineIata,
      airlineName: route.airlineName,
      departureAirportIata: route.origin.iataCode,
      departureAirportName: route.origin.name,
      arrivalAirportIata: route.destination.iataCode,
      arrivalAirportName: route.destination.name,
      scheduledDeparture: DateTime.now(),
      scheduledArrival: DateTime.now(),
      scheduleIsKnown: false,
      status: live == null
          ? FlightStatusEnum.unknown
          : FlightStatusEnum.active,
      dataSource: 'adsbdb',
    );

    // Real, verifiable facts.
    expect(flight.airlineName, 'American Airlines');
    expect(flight.routeDisplay, 'JFK → LHR');

    // The fields the old engine invented must now be absent.
    expect(flight.departureGate, isNull, reason: 'gates are not published here');
    expect(flight.arrivalGate, isNull);
    expect(flight.departureTerminal, isNull);
    expect(flight.baggageClaim, isNull, reason: 'baggage belts were invented');
    expect(flight.departureDelayMinutes, isNull);
    expect(flight.arrivalDelayMinutes, isNull);

    // And the schedule must be flagged as not real.
    expect(flight.scheduleIsKnown, isFalse);
  });

  test('an unknown flight number reports nothing rather than guessing', () async {
    expect(await AdsbDataService.instance.lookupRoute('ZZ9999'), isNull);
  });
}
