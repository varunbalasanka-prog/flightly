import '../models/models.dart';

/// Abstract interface for flight data providers.
///
/// This abstraction allows swapping Aviationstack for another
/// provider (FlightAware, AeroAPI, etc.) without changing
/// any UI or business logic.
abstract class FlightDataProvider {
  /// Search for flights by flight number (e.g. "AA123").
  /// Returns matching flights from the provider.
  Future<FlightLookupResult> searchFlight(
    String flightNumber, {
    DateTime? date,
  });

  /// Get the latest status for a monitored flight.
  Future<FlightStatusResult> getFlightStatus(String flightId);

  /// Get airport information by IATA code.
  Future<AirportInfo> getAirport(String iataCode);

  /// Get current quota status (global + user).
  Future<UsageQuota> getQuotaStatus();

  /// Set up monitoring for a flight (activates cron polling).
  Future<MonitorResult> setupMonitoring(String flightId);

  /// Stop monitoring a flight.
  Future<void> stopMonitoring(String flightId);
}

/// Result of a flight lookup/search.
class FlightLookupResult {
  final List<Flight> flights;
  final String? error;
  final bool quotaExhausted;
  final DateTime fetchedAt;
  final String source;

  const FlightLookupResult({
    this.flights = const [],
    this.error,
    this.quotaExhausted = false,
    required this.fetchedAt,
    this.source = 'aviationstack',
  });

  bool get hasResults => flights.isNotEmpty;
  bool get hasError => error != null;
}

/// Result of a flight status check.
class FlightStatusResult {
  final FlightStatus? status;
  final String? error;
  final bool quotaExhausted;
  final DateTime fetchedAt;
  final String source;

  const FlightStatusResult({
    this.status,
    this.error,
    this.quotaExhausted = false,
    required this.fetchedAt,
    this.source = 'aviationstack',
  });

  bool get hasStatus => status != null;
  bool get hasError => error != null;
}

/// Airport info result.
class AirportInfo {
  final AirportStatus? airport;
  final String? error;
  final DateTime fetchedAt;

  const AirportInfo({
    this.airport,
    this.error,
    required this.fetchedAt,
  });

  bool get hasData => airport != null;
}

/// Result of setting up flight monitoring.
class MonitorResult {
  final bool success;
  final String? error;
  final String? monitorId;

  const MonitorResult({
    required this.success,
    this.error,
    this.monitorId,
  });
}
