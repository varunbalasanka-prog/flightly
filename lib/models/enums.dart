/// Flight status enumeration matching Aviationstack values.
enum FlightStatusEnum {
  scheduled,
  active,
  landed,
  cancelled,
  diverted,
  incident,
  unknown;

  static FlightStatusEnum fromString(String? value) {
    if (value == null) return FlightStatusEnum.unknown;
    return FlightStatusEnum.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => FlightStatusEnum.unknown,
    );
  }

  String get displayName {
    switch (this) {
      case FlightStatusEnum.scheduled:
        return 'Scheduled';
      case FlightStatusEnum.active:
        return 'In Flight';
      case FlightStatusEnum.landed:
        return 'Landed';
      case FlightStatusEnum.cancelled:
        return 'Cancelled';
      case FlightStatusEnum.diverted:
        return 'Diverted';
      case FlightStatusEnum.incident:
        return 'Incident';
      case FlightStatusEnum.unknown:
        return 'Unknown';
    }
  }

  bool get isTerminal =>
      this == landed || this == cancelled || this == diverted;

  bool get isActive => this == active;

  bool get isAlert =>
      this == cancelled || this == diverted || this == incident;
}

/// Delay risk level for explainable delay scoring.
enum DelayRiskLevel {
  low,
  medium,
  high,
  unknown;

  String get displayName {
    switch (this) {
      case DelayRiskLevel.low:
        return 'Low Risk';
      case DelayRiskLevel.medium:
        return 'Medium Risk';
      case DelayRiskLevel.high:
        return 'High Risk';
      case DelayRiskLevel.unknown:
        return 'Unknown';
    }
  }
}

/// Connection status between flights.
enum ConnectionStatusEnum {
  safe,
  tight,
  atRisk,
  missed;

  String get displayName {
    switch (this) {
      case ConnectionStatusEnum.safe:
        return 'Safe';
      case ConnectionStatusEnum.tight:
        return 'Tight';
      case ConnectionStatusEnum.atRisk:
        return 'At Risk';
      case ConnectionStatusEnum.missed:
        return 'Missed';
    }
  }
}

/// Alert event types for notifications.
enum AlertEventType {
  departureDelay,
  arrivalDelay,
  gateChange,
  terminalChange,
  cancellation,
  diversion,
  landed,
  baggageClaim,
  connectionRisk,
  quotaExhausted;

  String get displayName {
    switch (this) {
      case AlertEventType.departureDelay:
        return 'Departure Delay';
      case AlertEventType.arrivalDelay:
        return 'Arrival Delay';
      case AlertEventType.gateChange:
        return 'Gate Change';
      case AlertEventType.terminalChange:
        return 'Terminal Change';
      case AlertEventType.cancellation:
        return 'Cancellation';
      case AlertEventType.diversion:
        return 'Diversion';
      case AlertEventType.landed:
        return 'Landed';
      case AlertEventType.baggageClaim:
        return 'Baggage';
      case AlertEventType.connectionRisk:
        return 'Connection Risk';
      case AlertEventType.quotaExhausted:
        return 'Quota Exhausted';
    }
  }
}

/// Sharing invite status.
enum ShareStatus {
  pending,
  accepted,
  revoked;
}
