import 'package:equatable/equatable.dart';
import 'enums.dart';
import 'flight.dart';

/// Delay risk assessment with explainable rules.
/// This is deterministic — NOT ML prediction.
class DelayRisk extends Equatable {
  final DelayRiskLevel level;
  final String explanation;
  final List<String> factors;
  final DateTime assessedAt;

  const DelayRisk({
    required this.level,
    required this.explanation,
    this.factors = const [],
    required this.assessedAt,
  });

  factory DelayRisk.fromJson(Map<String, dynamic> json) {
    return DelayRisk(
      level: DelayRiskLevel.values.firstWhere(
        (e) => e.name == (json['level'] as String? ?? 'unknown'),
        orElse: () => DelayRiskLevel.unknown,
      ),
      explanation: json['explanation'] as String? ?? 'Unavailable',
      factors: (json['factors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      assessedAt: json['assessed_at'] != null
          ? DateTime.parse(json['assessed_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'explanation': explanation,
    'factors': factors,
    'assessed_at': assessedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [level, explanation, assessedAt];
}

/// Snapshot of flight status at a point in time.
class FlightStatus extends Equatable {
  final String id;
  final String flightId;
  final FlightStatusEnum status;
  final int? departureDelay;
  final int? arrivalDelay;
  final String? departureGate;
  final String? arrivalGate;
  final String? departureTerminal;
  final String? arrivalTerminal;
  final String? baggageClaim;
  final DateTime? estimatedDeparture;
  final DateTime? estimatedArrival;
  final DateTime? actualDeparture;
  final DateTime? actualArrival;
  final String? aircraftIcao;
  final String? aircraftRegistration;
  final DelayRisk? delayRisk;
  final String? dataSource;
  final DateTime fetchedAt;

  const FlightStatus({
    required this.id,
    required this.flightId,
    required this.status,
    this.departureDelay,
    this.arrivalDelay,
    this.departureGate,
    this.arrivalGate,
    this.departureTerminal,
    this.arrivalTerminal,
    this.baggageClaim,
    this.estimatedDeparture,
    this.estimatedArrival,
    this.actualDeparture,
    this.actualArrival,
    this.aircraftIcao,
    this.aircraftRegistration,
    this.delayRisk,
    this.dataSource,
    required this.fetchedAt,
  });

  /// Whether this data is older than the stale threshold.
  bool get isStale {
    final age = DateTime.now().difference(fetchedAt);
    return age.inMinutes > 30;
  }

  /// Map of field names to whether the provider returned them.
  Map<String, bool> get availabilityFlags => {
    'departure_gate': departureGate != null,
    'arrival_gate': arrivalGate != null,
    'departure_terminal': departureTerminal != null,
    'arrival_terminal': arrivalTerminal != null,
    'baggage_claim': baggageClaim != null,
    'departure_delay': departureDelay != null,
    'arrival_delay': arrivalDelay != null,
    'aircraft': aircraftIcao != null || aircraftRegistration != null,
    'delay_risk': delayRisk != null,
  };

  factory FlightStatus.fromJson(Map<String, dynamic> json) {
    return FlightStatus(
      id: json['id'] as String,
      flightId: json['flight_id'] as String,
      status: FlightStatusEnum.fromString(json['status'] as String?),
      departureDelay: json['dep_delay_minutes'] as int?,
      arrivalDelay: json['arr_delay_minutes'] as int?,
      departureGate: json['dep_gate'] as String?,
      arrivalGate: json['arr_gate'] as String?,
      departureTerminal: json['dep_terminal'] as String?,
      arrivalTerminal: json['arr_terminal'] as String?,
      baggageClaim: json['baggage_claim'] as String?,
      estimatedDeparture: json['estimated_departure'] != null
          ? DateTime.parse(json['estimated_departure'] as String)
          : null,
      estimatedArrival: json['estimated_arrival'] != null
          ? DateTime.parse(json['estimated_arrival'] as String)
          : null,
      actualDeparture: json['actual_departure'] != null
          ? DateTime.parse(json['actual_departure'] as String)
          : null,
      actualArrival: json['actual_arrival'] != null
          ? DateTime.parse(json['actual_arrival'] as String)
          : null,
      aircraftIcao: json['aircraft_icao'] as String?,
      aircraftRegistration: json['aircraft_registration'] as String?,
      delayRisk: json['delay_risk'] != null
          ? DelayRisk.fromJson(json['delay_risk'] as Map<String, dynamic>)
          : null,
      dataSource: json['data_source'] as String?,
      fetchedAt: json['fetched_at'] != null
          ? DateTime.parse(json['fetched_at'] as String)
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, flightId, status, fetchedAt];
}

/// Usage quota state for the app.
class UsageQuota extends Equatable {
  final int globalRequestsUsed;
  final int globalRequestsLimit;
  final int userMonthlyFlightsUsed;
  final int userMonthlyFlightsLimit;
  final int userActiveMonitoredCount;
  final int userActiveMonitoredLimit;
  final DateTime? quotaResetsAt;

  const UsageQuota({
    required this.globalRequestsUsed,
    required this.globalRequestsLimit,
    required this.userMonthlyFlightsUsed,
    required this.userMonthlyFlightsLimit,
    required this.userActiveMonitoredCount,
    required this.userActiveMonitoredLimit,
    this.quotaResetsAt,
  });

  bool get isQuotaExhausted => globalRequestsUsed >= globalRequestsLimit;

  bool get canMonitorNewFlight =>
      userActiveMonitoredCount < userActiveMonitoredLimit &&
      userMonthlyFlightsUsed < userMonthlyFlightsLimit &&
      !isQuotaExhausted;

  double get globalUsagePercent =>
      globalRequestsLimit > 0
          ? (globalRequestsUsed / globalRequestsLimit).clamp(0.0, 1.0)
          : 0.0;

  int get globalRequestsRemaining =>
      (globalRequestsLimit - globalRequestsUsed).clamp(0, globalRequestsLimit);

  factory UsageQuota.fromJson(Map<String, dynamic> json) {
    return UsageQuota(
      globalRequestsUsed: json['global_requests_used'] as int? ?? 0,
      globalRequestsLimit: json['global_requests_limit'] as int? ?? 100,
      userMonthlyFlightsUsed: json['user_monthly_flights_used'] as int? ?? 0,
      userMonthlyFlightsLimit: json['user_monthly_flights_limit'] as int? ?? 2,
      userActiveMonitoredCount: json['user_active_monitored_count'] as int? ?? 0,
      userActiveMonitoredLimit: json['user_active_monitored_limit'] as int? ?? 1,
      quotaResetsAt: json['quota_resets_at'] != null
          ? DateTime.parse(json['quota_resets_at'] as String)
          : null,
    );
  }

  static const empty = UsageQuota(
    globalRequestsUsed: 0,
    globalRequestsLimit: 100,
    userMonthlyFlightsUsed: 0,
    userMonthlyFlightsLimit: 2,
    userActiveMonitoredCount: 0,
    userActiveMonitoredLimit: 1,
  );

  @override
  List<Object?> get props => [
    globalRequestsUsed,
    userMonthlyFlightsUsed,
    userActiveMonitoredCount,
  ];
}

/// Alert event for push notifications.
class AlertEvent extends Equatable {
  final String id;
  final String userId;
  final String flightId;
  final AlertEventType eventType;
  final String title;
  final String body;
  final Map<String, dynamic>? metadata;
  final bool isSent;
  final DateTime createdAt;

  const AlertEvent({
    required this.id,
    required this.userId,
    required this.flightId,
    required this.eventType,
    required this.title,
    required this.body,
    this.metadata,
    this.isSent = false,
    required this.createdAt,
  });

  factory AlertEvent.fromJson(Map<String, dynamic> json) {
    return AlertEvent(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      flightId: json['flight_id'] as String,
      eventType: AlertEventType.values.firstWhere(
        (e) => e.name == (json['event_type'] as String? ?? ''),
        orElse: () => AlertEventType.departureDelay,
      ),
      title: json['title'] as String,
      body: json['body'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      isSent: json['is_sent'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, flightId, eventType];
}

/// Flight sharing invite.
class FlightShare extends Equatable {
  final String id;
  final String flightId;
  final String ownerId;
  final String? sharedWithId;
  final String? inviteEmail;
  final String? inviteCode;
  final ShareStatus status;
  final bool isReadOnly;
  final DateTime createdAt;

  const FlightShare({
    required this.id,
    required this.flightId,
    required this.ownerId,
    this.sharedWithId,
    this.inviteEmail,
    this.inviteCode,
    this.status = ShareStatus.pending,
    this.isReadOnly = true,
    required this.createdAt,
  });

  factory FlightShare.fromJson(Map<String, dynamic> json) {
    return FlightShare(
      id: json['id'] as String,
      flightId: json['flight_id'] as String,
      ownerId: json['owner_id'] as String,
      sharedWithId: json['shared_with_id'] as String?,
      inviteEmail: json['invite_email'] as String?,
      inviteCode: json['invite_code'] as String?,
      status: ShareStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'pending'),
        orElse: () => ShareStatus.pending,
      ),
      isReadOnly: json['is_read_only'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, flightId, status];
}

/// Connection between two flights.
class Connection extends Equatable {
  final Flight inboundFlight;
  final Flight outboundFlight;
  final ConnectionStatusEnum status;
  final int connectionMinutes;
  final int minimumConnectionMinutes;
  final String explanation;

  const Connection({
    required this.inboundFlight,
    required this.outboundFlight,
    required this.status,
    required this.connectionMinutes,
    this.minimumConnectionMinutes = 60,
    required this.explanation,
  });

  bool get isSameAirport =>
      inboundFlight.arrivalAirportIata == outboundFlight.departureAirportIata;

  @override
  List<Object?> get props => [
    inboundFlight.id,
    outboundFlight.id,
    status,
    connectionMinutes,
  ];
}

/// Airport status information.
class AirportStatus extends Equatable {
  final String iataCode;
  final String? icaoCode;
  final String? name;
  final String? city;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? timezone;
  final int delayMinutes;
  final String weatherCondition;
  final int temperatureC;
  final int activeFlightsCount;

  const AirportStatus({
    required this.iataCode,
    this.icaoCode,
    this.name,
    this.city,
    this.country,
    this.latitude,
    this.longitude,
    this.timezone,
    this.delayMinutes = 0,
    this.weatherCondition = 'Clear',
    this.temperatureC = 22,
    this.activeFlightsCount = 0,
  });

  factory AirportStatus.fromJson(Map<String, dynamic> json) {
    return AirportStatus(
      iataCode: json['iata_code'] as String? ?? json['iata'] as String? ?? '',
      icaoCode: json['icao_code'] as String? ?? json['icao'] as String?,
      name: json['airport_name'] as String? ?? json['name'] as String?,
      city: json['city'] as String?,
      country: json['country_name'] as String? ?? json['country'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      timezone: json['timezone'] as String?,
      delayMinutes: (json['delay_minutes'] as num?)?.toInt() ?? 0,
      weatherCondition: json['weather_condition'] as String? ?? 'Clear',
      temperatureC: (json['temperature_c'] as num?)?.toInt() ?? 22,
      activeFlightsCount: (json['active_flights_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [iataCode, icaoCode, delayMinutes, weatherCondition];
}
