import '../models/models.dart';

/// Normalizes raw Aviationstack flight status strings
/// into our domain FlightStatusEnum.
class StatusNormalizer {
  const StatusNormalizer();

  /// Normalize Aviationstack `flight_status` field.
  FlightStatusEnum normalize(String? rawStatus) {
    if (rawStatus == null || rawStatus.isEmpty) {
      return FlightStatusEnum.unknown;
    }

    switch (rawStatus.toLowerCase().trim()) {
      case 'scheduled':
        return FlightStatusEnum.scheduled;
      case 'active':
      case 'en-route':
      case 'en_route':
      case 'in_air':
      case 'airborne':
        return FlightStatusEnum.active;
      case 'landed':
      case 'arrived':
        return FlightStatusEnum.landed;
      case 'cancelled':
      case 'canceled':
        return FlightStatusEnum.cancelled;
      case 'diverted':
        return FlightStatusEnum.diverted;
      case 'incident':
        return FlightStatusEnum.incident;
      default:
        return FlightStatusEnum.unknown;
    }
  }

  /// Build a Flight from a raw Aviationstack `/v1/flights` response item.
  Flight? fromAviationstackResponse(Map<String, dynamic> raw) {
    try {
      final flight = raw['flight'] as Map<String, dynamic>?;
      final departure = raw['departure'] as Map<String, dynamic>?;
      final arrival = raw['arrival'] as Map<String, dynamic>?;
      final airline = raw['airline'] as Map<String, dynamic>?;
      final aircraft = raw['aircraft'] as Map<String, dynamic>?;

      if (flight == null || departure == null || arrival == null) return null;

      final flightIata = flight['iata'] as String?;
      if (flightIata == null || flightIata.isEmpty) return null;

      final scheduledDep = departure['scheduled'] as String?;
      final scheduledArr = arrival['scheduled'] as String?;
      if (scheduledDep == null || scheduledArr == null) return null;

      return Flight(
        id: '', // Will be assigned by Supabase
        flightNumber: flightIata,
        airlineIata: airline?['iata'] as String? ?? '',
        airlineName: airline?['name'] as String?,
        departureAirportIata: departure['iata'] as String? ?? '',
        departureAirportName: departure['airport'] as String?,
        arrivalAirportIata: arrival['iata'] as String? ?? '',
        arrivalAirportName: arrival['airport'] as String?,
        scheduledDeparture: DateTime.parse(scheduledDep),
        scheduledArrival: DateTime.parse(scheduledArr),
        estimatedDeparture: _tryParse(departure['estimated'] as String?),
        estimatedArrival: _tryParse(arrival['estimated'] as String?),
        actualDeparture: _tryParse(departure['actual'] as String?),
        actualArrival: _tryParse(arrival['actual'] as String?),
        departureTerminal: departure['terminal'] as String?,
        departureGate: departure['gate'] as String?,
        arrivalTerminal: arrival['terminal'] as String?,
        arrivalGate: arrival['gate'] as String?,
        baggageClaim: arrival['baggage'] as String?,
        departureDelayMinutes: departure['delay'] as int?,
        arrivalDelayMinutes: arrival['delay'] as int?,
        status: normalize(raw['flight_status'] as String?),
        aircraft: aircraft != null
            ? Aircraft(
                registration: aircraft['registration'] as String?,
                icaoCode: aircraft['icao24'] as String?,
                modelName: aircraft['iata'] as String?,
              )
            : null,
        dataSource: 'aviationstack',
        lastUpdated: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  DateTime? _tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
}
