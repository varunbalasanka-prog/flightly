import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../config/app_config.dart';
import '../services/aviation_data_service.dart';
import 'flight_data_provider.dart';

/// Supabase-backed implementation of [FlightDataProvider] with
/// intelligent zero-key OpenSky fallback.
class SupabaseFlightProvider implements FlightDataProvider {
  final SupabaseClient _client;

  SupabaseFlightProvider(this._client);

  @override
  Future<FlightLookupResult> searchFlight(
    String flightNumber, {
    DateTime? date,
  }) async {
    final cleanNum = flightNumber.toUpperCase().trim();
    if (cleanNum.isEmpty) {
      return FlightLookupResult(
        error: 'Flight number is required',
        fetchedAt: DateTime.now(),
      );
    }

    try {
      // 1. Try Supabase Edge function if available
      final response = await _client.functions.invoke(
        'flight-lookup',
        body: {
          'flight_number': cleanNum,
          if (date != null) 'date': date.toIso8601String(),
        },
      ).timeout(const Duration(seconds: 3));

      final data = response.data as Map<String, dynamic>?;
      if (data != null && data['flights'] is List && (data['flights'] as List).isNotEmpty) {
        final flights = (data['flights'] as List)
            .map((f) => Flight.fromJson(f as Map<String, dynamic>))
            .toList();
        return FlightLookupResult(
          flights: flights,
          fetchedAt: DateTime.now(),
          source: data['source'] as String? ?? 'aviationstack',
        );
      }
    } catch (_) {
      // Fallback seamlessly to free & zero-key OpenSky + Aviation Engine
    }

    // 2. Query free OpenSky + Aviation Data Engine
    return AviationDataService.instance.searchFlight(cleanNum);
  }

  @override
  Future<FlightStatusResult> getFlightStatus(String flightId) async {
    try {
      // Read latest status snapshot from Supabase
      final response = await _client
          .from('status_snapshots')
          .select()
          .eq('flight_id', flightId)
          .order('fetched_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return FlightStatusResult(
          status: FlightStatus.fromJson(response),
          fetchedAt: DateTime.now(),
          source: response['data_source'] as String? ?? 'openskynetwork',
        );
      }
    } catch (_) {}

    return FlightStatusResult(
      error: 'No snapshot available yet',
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Future<AirportInfo> getAirport(String iataCode) async {
    try {
      final res = await _client
          .from('airports')
          .select()
          .eq('iata_code', iataCode.toUpperCase().trim())
          .maybeSingle();

      if (res != null) {
        return AirportInfo(
          airport: AirportStatus(
            iataCode: res['iata_code'] as String,
            icaoCode: res['icao_code'] as String?,
            name: res['name'] as String,
            city: res['city'] as String,
            country: res['country'] as String,
            latitude: (res['latitude'] as num).toDouble(),
            longitude: (res['longitude'] as num).toDouble(),
            delayMinutes: (res['delay_index'] as num?)?.toInt() ?? 0,
            weatherCondition: res['weather_condition'] as String? ?? 'Clear',
            temperatureC: 22,
            activeFlightsCount: 35,
          ),
          fetchedAt: DateTime.now(),
        );
      }
    } catch (_) {}

    return AviationDataService.instance.getAirport(iataCode);
  }

  @override
  Future<UsageQuota> getQuotaStatus() async {
    // Every per-user figure here used to be a hard-coded literal (1 of 10
    // flights, 1 of 5 monitors) that ignored both the database and
    // AppConfig, so the quota UI showed the same invented numbers to
    // everyone regardless of actual usage.
    final periodStart = _currentPeriodStart();

    var globalUsed = 0;
    var globalLimit = AppConfig.globalMonthlyRequestLimit;
    DateTime? resetsAt;

    try {
      final res = await _client
          .from('usage_quotas')
          .select()
          .eq('period_start', periodStart.toIso8601String())
          .maybeSingle();

      if (res != null) {
        globalUsed = (res['global_requests_used'] as num?)?.toInt() ?? 0;
        globalLimit = (res['global_requests_limit'] as num?)?.toInt() ?? globalLimit;
        resetsAt = DateTime.tryParse(res['period_end'] as String? ?? '');
      }
    } catch (_) {
      // Fall through with defaults; the banner treats this as "unknown usage".
    }

    var flightsUsed = 0;
    var flightsLimit = AppConfig.userMonthlyFlightLimit;
    var monitoredCount = 0;
    var monitoredLimit = AppConfig.userActiveMonitoredLimit;

    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final res = await _client
            .from('user_quotas')
            .select()
            .eq('user_id', user.id)
            .eq('period_start', periodStart.toIso8601String())
            .maybeSingle();

        if (res != null) {
          flightsUsed = (res['monthly_flights_used'] as num?)?.toInt() ?? 0;
          flightsLimit =
              (res['monthly_flights_limit'] as num?)?.toInt() ?? flightsLimit;
          monitoredCount =
              (res['active_monitored_count'] as num?)?.toInt() ?? 0;
          monitoredLimit =
              (res['active_monitored_limit'] as num?)?.toInt() ?? monitoredLimit;
        }
      } catch (_) {}
    }

    return UsageQuota(
      globalRequestsUsed: globalUsed,
      globalRequestsLimit: globalLimit,
      userMonthlyFlightsUsed: flightsUsed,
      userMonthlyFlightsLimit: flightsLimit,
      userActiveMonitoredCount: monitoredCount,
      userActiveMonitoredLimit: monitoredLimit,
      quotaResetsAt: resetsAt,
    );
  }

  /// Start of the current UTC month, matching `date_trunc('month', NOW())`
  /// as used by the quota stored procedures.
  static DateTime _currentPeriodStart() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month);
  }

  @override
  Future<MonitorResult> setupMonitoring(String flightId) async {
    // This used to upsert straight into `monitored_flights`, which skipped the
    // monitor-setup Edge Function entirely -- and with it the per-user active
    // monitor quota. It also reported success when nobody was signed in.
    final user = _client.auth.currentUser;
    if (user == null) {
      return const MonitorResult(
        success: false,
        error: 'You must be signed in to monitor a flight',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'monitor-setup',
        body: {'flightId': flightId},
      );

      final data = response.data as Map<String, dynamic>?;
      if (response.status == 200 && data?['success'] == true) {
        return const MonitorResult(success: true);
      }
      return MonitorResult(
        success: false,
        error: data?['error'] as String? ?? 'Could not start monitoring',
      );
    } catch (e) {
      return const MonitorResult(
        success: false,
        error: 'Could not start monitoring. Please try again.',
      );
    }
  }

  @override
  Future<void> stopMonitoring(String flightId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final updated = await _client
          .from('monitored_flights')
          .update({'is_active': false})
          .eq('flight_id', flightId)
          .eq('user_id', user.id)
          .eq('is_active', true)
          .select();

      // Release the monitoring slot. Without this the count only ever grew and
      // users were permanently locked out once they hit the active limit.
      if (updated.isEmpty) return;

      final periodStart = _currentPeriodStart().toIso8601String();
      final quota = await _client
          .from('user_quotas')
          .select('active_monitored_count')
          .eq('user_id', user.id)
          .eq('period_start', periodStart)
          .maybeSingle();

      final count = (quota?['active_monitored_count'] as num?)?.toInt() ?? 0;
      if (count > 0) {
        await _client
            .from('user_quotas')
            .update({'active_monitored_count': count - 1})
            .eq('user_id', user.id)
            .eq('period_start', periodStart);
      }
    } catch (_) {}
  }
}
