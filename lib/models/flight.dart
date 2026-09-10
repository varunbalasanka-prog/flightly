import 'package:equatable/equatable.dart';
import 'enums.dart';

/// Core flight model representing a tracked flight.
///
/// Maps to the `flights` Supabase table + enriched data
/// from status snapshots. Null fields indicate the provider
/// did not return that data — never fabricate values.
class Flight extends Equatable {
  final String id;
  final String flightNumber;
  final String airlineIata;
  final String? airlineName;
  final String departureAirportIata;
  final String? departureAirportName;
  final String arrivalAirportIata;
  final String? arrivalAirportName;
  final DateTime scheduledDeparture;
  final DateTime scheduledArrival;
  final DateTime? estimatedDeparture;
  final DateTime? estimatedArrival;
  final DateTime? actualDeparture;
  final DateTime? actualArrival;
  final String? departureTerminal;
  final String? departureGate;
  final String? arrivalTerminal;
  final String? arrivalGate;
  final String? baggageClaim;
  final int? departureDelayMinutes;
  final int? arrivalDelayMinutes;
  final FlightStatusEnum status;
  final Aircraft? aircraft;
  final String? tripId;
  final bool isManualEntry;
  final bool isHistory;
  final DateTime? lastUpdated;
  final String? dataSource;

  const Flight({
    required this.id,
    required this.flightNumber,
    required this.airlineIata,
    this.airlineName,
    required this.departureAirportIata,
    this.departureAirportName,
    required this.arrivalAirportIata,
    this.arrivalAirportName,
    required this.scheduledDeparture,
    required this.scheduledArrival,
    this.estimatedDeparture,
    this.estimatedArrival,
    this.actualDeparture,
    this.actualArrival,
    this.departureTerminal,
    this.departureGate,
    this.arrivalTerminal,
    this.arrivalGate,
    this.baggageClaim,
    this.departureDelayMinutes,
    this.arrivalDelayMinutes,
    this.status = FlightStatusEnum.scheduled,
    this.aircraft,
    this.tripId,
    this.isManualEntry = false,
    this.isHistory = false,
    this.lastUpdated,
    this.dataSource,
  });

  /// The best-known departure time (actual > estimated > scheduled).
  DateTime get bestDepartureTime =>
      actualDeparture ?? estimatedDeparture ?? scheduledDeparture;

  /// The best-known arrival time (actual > estimated > scheduled).
  DateTime get bestArrivalTime =>
      actualArrival ?? estimatedArrival ?? scheduledArrival;

  /// Route string e.g. "DFW → DCA"
  String get routeDisplay =>
      '$departureAirportIata → $arrivalAirportIata';

  /// Whether this flight has gate information available.
  bool get hasGateInfo =>
      departureGate != null || arrivalGate != null;

  /// Whether this flight is being actively monitored.
  bool get isDelayed =>
      (departureDelayMinutes != null && departureDelayMinutes! > 0) ||
      (arrivalDelayMinutes != null && arrivalDelayMinutes! > 0);

  Flight copyWith({
    String? id,
    String? flightNumber,
    String? airlineIata,
    String? airlineName,
    String? departureAirportIata,
    String? departureAirportName,
    String? arrivalAirportIata,
    String? arrivalAirportName,
    DateTime? scheduledDeparture,
    DateTime? scheduledArrival,
    DateTime? estimatedDeparture,
    DateTime? estimatedArrival,
    DateTime? actualDeparture,
    DateTime? actualArrival,
    String? departureTerminal,
    String? departureGate,
    String? arrivalTerminal,
    String? arrivalGate,
    String? baggageClaim,
    int? departureDelayMinutes,
    int? arrivalDelayMinutes,
    FlightStatusEnum? status,
    Aircraft? aircraft,
    String? tripId,
    bool? isManualEntry,
    bool? isHistory,
    DateTime? lastUpdated,
    String? dataSource,
  }) {
    return Flight(
      id: id ?? this.id,
      flightNumber: flightNumber ?? this.flightNumber,
      airlineIata: airlineIata ?? this.airlineIata,
      airlineName: airlineName ?? this.airlineName,
      departureAirportIata: departureAirportIata ?? this.departureAirportIata,
      departureAirportName: departureAirportName ?? this.departureAirportName,
      arrivalAirportIata: arrivalAirportIata ?? this.arrivalAirportIata,
      arrivalAirportName: arrivalAirportName ?? this.arrivalAirportName,
      scheduledDeparture: scheduledDeparture ?? this.scheduledDeparture,
      scheduledArrival: scheduledArrival ?? this.scheduledArrival,
      estimatedDeparture: estimatedDeparture ?? this.estimatedDeparture,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      actualDeparture: actualDeparture ?? this.actualDeparture,
      actualArrival: actualArrival ?? this.actualArrival,
      departureTerminal: departureTerminal ?? this.departureTerminal,
      departureGate: departureGate ?? this.departureGate,
      arrivalTerminal: arrivalTerminal ?? this.arrivalTerminal,
      arrivalGate: arrivalGate ?? this.arrivalGate,
      baggageClaim: baggageClaim ?? this.baggageClaim,
      departureDelayMinutes: departureDelayMinutes ?? this.departureDelayMinutes,
      arrivalDelayMinutes: arrivalDelayMinutes ?? this.arrivalDelayMinutes,
      status: status ?? this.status,
      aircraft: aircraft ?? this.aircraft,
      tripId: tripId ?? this.tripId,
      isManualEntry: isManualEntry ?? this.isManualEntry,
      isHistory: isHistory ?? this.isHistory,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      dataSource: dataSource ?? this.dataSource,
    );
  }

  factory Flight.fromJson(Map<String, dynamic> json) {
    return Flight(
      id: json['id'] as String,
      flightNumber: json['flight_number'] as String,
      airlineIata: json['airline_iata'] as String? ?? '',
      airlineName: json['airline_name'] as String?,
      departureAirportIata: json['dep_airport_iata'] as String,
      departureAirportName: json['dep_airport_name'] as String?,
      arrivalAirportIata: json['arr_airport_iata'] as String,
      arrivalAirportName: json['arr_airport_name'] as String?,
      scheduledDeparture: DateTime.parse(json['scheduled_departure'] as String),
      scheduledArrival: DateTime.parse(json['scheduled_arrival'] as String),
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
      departureTerminal: json['dep_terminal'] as String?,
      departureGate: json['dep_gate'] as String?,
      arrivalTerminal: json['arr_terminal'] as String?,
      arrivalGate: json['arr_gate'] as String?,
      baggageClaim: json['baggage_claim'] as String?,
      departureDelayMinutes: json['dep_delay_minutes'] as int?,
      arrivalDelayMinutes: json['arr_delay_minutes'] as int?,
      status: FlightStatusEnum.fromString(json['status'] as String?),
      aircraft: json['aircraft'] != null
          ? Aircraft.fromJson(json['aircraft'] as Map<String, dynamic>)
          : null,
      tripId: json['trip_id'] as String?,
      isManualEntry: json['is_manual_entry'] as bool? ?? false,
      isHistory: json['is_history'] as bool? ?? false,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : null,
      dataSource: json['data_source'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'flight_number': flightNumber,
      'airline_iata': airlineIata,
      'airline_name': airlineName,
      'dep_airport_iata': departureAirportIata,
      'dep_airport_name': departureAirportName,
      'arr_airport_iata': arrivalAirportIata,
      'arr_airport_name': arrivalAirportName,
      'scheduled_departure': scheduledDeparture.toIso8601String(),
      'scheduled_arrival': scheduledArrival.toIso8601String(),
      'estimated_departure': estimatedDeparture?.toIso8601String(),
      'estimated_arrival': estimatedArrival?.toIso8601String(),
      'actual_departure': actualDeparture?.toIso8601String(),
      'actual_arrival': actualArrival?.toIso8601String(),
      'dep_terminal': departureTerminal,
      'dep_gate': departureGate,
      'arr_terminal': arrivalTerminal,
      'arr_gate': arrivalGate,
      'baggage_claim': baggageClaim,
      'dep_delay_minutes': departureDelayMinutes,
      'arr_delay_minutes': arrivalDelayMinutes,
      'status': status.name,
      'aircraft': aircraft?.toJson(),
      'trip_id': tripId,
      'is_manual_entry': isManualEntry,
      'is_history': isHistory,
      'last_updated': lastUpdated?.toIso8601String(),
      'data_source': dataSource,
    };
    if (id.isNotEmpty && id.length == 36) {
      map['id'] = id;
    }
    return map;
  }

  @override
  List<Object?> get props => [id, flightNumber, status, lastUpdated];
}

/// Aircraft information associated with a flight.
class Aircraft extends Equatable {
  final String? registration;
  final String? icaoCode;
  final String? modelName;
  final String? airlineIata;

  const Aircraft({
    this.registration,
    this.icaoCode,
    this.modelName,
    this.airlineIata,
  });

  factory Aircraft.fromJson(Map<String, dynamic> json) {
    return Aircraft(
      registration: json['registration'] as String?,
      icaoCode: json['icao_code'] as String? ?? json['icao24'] as String?,
      modelName: json['model_name'] as String? ?? json['iata_type'] as String?,
      airlineIata: json['airline_iata'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'registration': registration,
    'icao_code': icaoCode,
    'model_name': modelName,
    'airline_iata': airlineIata,
  };

  @override
  List<Object?> get props => [registration, icaoCode];
}
