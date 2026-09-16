import '../models/models.dart';

/// Calculates connection risk between an inbound and outbound flight.
class ConnectionCalculator {
  const ConnectionCalculator();

  /// Minimum connection time defaults.
  static const int defaultMinimumMinutes = 60;
  static const int tightThresholdMinutes = 45;

  Connection calculate({
    required Flight inboundFlight,
    required Flight outboundFlight,
    int minimumConnectionMinutes = defaultMinimumMinutes,
  }) {
    // Use best-known times
    final arrivalTime = inboundFlight.bestArrivalTime;
    final departureTime = outboundFlight.bestDepartureTime;

    final connectionMinutes = departureTime.difference(arrivalTime).inMinutes;

    // Check airport match
    final sameAirport =
        inboundFlight.arrivalAirportIata == outboundFlight.departureAirportIata;

    ConnectionStatusEnum status;
    String explanation;

    if (!sameAirport) {
      status = ConnectionStatusEnum.missed;
      explanation =
          'Different airports: ${inboundFlight.arrivalAirportIata} → '
          '${outboundFlight.departureAirportIata}';
    } else if (inboundFlight.status == FlightStatusEnum.cancelled) {
      status = ConnectionStatusEnum.missed;
      explanation = 'Inbound flight ${inboundFlight.flightNumber} cancelled';
    } else if (connectionMinutes < 0) {
      status = ConnectionStatusEnum.missed;
      explanation =
          'Outbound departs ${-connectionMinutes}min before inbound arrives';
    } else if (connectionMinutes < tightThresholdMinutes) {
      status = ConnectionStatusEnum.atRisk;
      explanation =
          '${connectionMinutes}min connection at '
          '${outboundFlight.departureAirportIata} — below minimum '
          '${minimumConnectionMinutes}min';
    } else if (connectionMinutes < minimumConnectionMinutes) {
      status = ConnectionStatusEnum.tight;
      explanation =
          '${connectionMinutes}min connection at '
          '${outboundFlight.departureAirportIata} — tight but possible';
    } else {
      status = ConnectionStatusEnum.safe;
      explanation =
          '${connectionMinutes}min connection at '
          '${outboundFlight.departureAirportIata} — comfortable';
    }

    // Adjust if inbound is delayed.
    //
    // Only when the delay is NOT already reflected in the arrival time.
    // `bestArrivalTime` prefers actual/estimated arrival, which an airline
    // reports with the delay baked in -- subtracting `arrivalDelayMinutes`
    // again counted it twice and turned a comfortable 60min connection into
    // "effective connection 30min / At Risk".
    final delayAlreadyInArrivalTime = inboundFlight.actualArrival != null ||
        inboundFlight.estimatedArrival != null;

    if (inboundFlight.isDelayed &&
        !delayAlreadyInArrivalTime &&
        status == ConnectionStatusEnum.safe) {
      final delay = inboundFlight.arrivalDelayMinutes ?? 0;
      final effective = connectionMinutes - delay;
      if (effective < tightThresholdMinutes) {
        status = ConnectionStatusEnum.atRisk;
        explanation =
            'Inbound delayed ${delay}min — effective connection ${effective}min';
      } else if (effective < minimumConnectionMinutes) {
        status = ConnectionStatusEnum.tight;
        explanation =
            'Inbound delayed ${delay}min — connection now ${effective}min';
      }
    }

    return Connection(
      inboundFlight: inboundFlight,
      outboundFlight: outboundFlight,
      status: status,
      connectionMinutes: connectionMinutes,
      minimumConnectionMinutes: minimumConnectionMinutes,
      explanation: explanation,
    );
  }
}
