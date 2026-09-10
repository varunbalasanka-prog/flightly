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

    // Adjust if inbound is delayed
    if (inboundFlight.isDelayed && status == ConnectionStatusEnum.safe) {
      final delay = inboundFlight.arrivalDelayMinutes ?? 0;
      if (connectionMinutes - delay < tightThresholdMinutes) {
        status = ConnectionStatusEnum.atRisk;
        explanation =
            'Inbound delayed ${delay}min — effective connection '
            '${connectionMinutes - delay}min';
      } else if (connectionMinutes - delay < minimumConnectionMinutes) {
        status = ConnectionStatusEnum.tight;
        explanation =
            'Inbound delayed ${delay}min — connection now '
            '${connectionMinutes - delay}min';
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
