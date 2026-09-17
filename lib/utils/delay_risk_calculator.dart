import '../models/models.dart';

/// Deterministic, explainable delay-risk scoring.
///
/// This is NOT ML prediction — it uses simple threshold rules
/// on provider timestamps and inbound aircraft status.
/// Each rule produces a human-readable explanation.
class DelayRiskCalculator {
  const DelayRiskCalculator();

  DelayRisk calculate({
    required Flight flight,
    FlightStatus? latestStatus,
    Flight? inboundAircraftFlight,
    List<String> weatherConcerns = const [],
    InboundAircraftPosition? inboundPosition,
    DateTime? now,
  }) {
    final factors = <String>[];
    var highestRisk = DelayRiskLevel.unknown;

    // ── Rule 1: Current departure delay ──
    final depDelay = latestStatus?.departureDelay ?? flight.departureDelayMinutes;
    if (depDelay != null) {
      if (depDelay >= 60) {
        highestRisk = _elevate(highestRisk, DelayRiskLevel.high);
        factors.add('Departure delayed $depDelay minutes');
      } else if (depDelay >= 15) {
        highestRisk = _elevate(highestRisk, DelayRiskLevel.medium);
        factors.add('Moderate departure delay of $depDelay minutes');
      } else if (depDelay > 0) {
        highestRisk = _elevate(highestRisk, DelayRiskLevel.low);
        factors.add('Minor departure delay of $depDelay minutes');
      }
    }

    // ── Rule 2: Arrival delay (if known) ──
    final arrDelay = latestStatus?.arrivalDelay ?? flight.arrivalDelayMinutes;
    if (arrDelay != null && arrDelay >= 30) {
      highestRisk = _elevate(highestRisk, DelayRiskLevel.medium);
      factors.add('Arrival expected $arrDelay minutes late');
    }

    // ── Rule 3: Inbound aircraft delay ──
    if (inboundAircraftFlight != null) {
      final inboundDelay = inboundAircraftFlight.arrivalDelayMinutes;
      if (inboundDelay != null) {
        if (inboundDelay >= 45) {
          highestRisk = _elevate(highestRisk, DelayRiskLevel.high);
          factors.add('Inbound aircraft delayed $inboundDelay min — likely late departure');
        } else if (inboundDelay >= 15) {
          highestRisk = _elevate(highestRisk, DelayRiskLevel.medium);
          factors.add('Inbound aircraft running ${inboundDelay}min late');
        }
      }

      if (inboundAircraftFlight.status == FlightStatusEnum.cancelled) {
        highestRisk = DelayRiskLevel.high;
        factors.add('Inbound aircraft flight cancelled — high risk of disruption');
      }

      if (inboundAircraftFlight.status == FlightStatusEnum.diverted) {
        highestRisk = DelayRiskLevel.high;
        factors.add('Inbound aircraft diverted — aircraft may not be available');
      }
    }

    // ── Rule 4: Estimated vs scheduled drift ──
    final estDep = latestStatus?.estimatedDeparture ?? flight.estimatedDeparture;
    if (estDep != null && depDelay == null) {
      final drift = estDep.difference(flight.scheduledDeparture).inMinutes;
      if (drift > 5) {
        highestRisk = _elevate(highestRisk, DelayRiskLevel.low);
        factors.add('Minor schedule adjustment detected (+${drift}min)');
      }
    }

    // ── Rule 6: Observed weather at either airport (METAR) ──
    for (final concern in weatherConcerns) {
      final severe = concern.contains('LIFR') || concern.contains('Thunderstorm') || concern.contains('Strong winds');
      highestRisk = _elevate(highestRisk, severe ? DelayRiskLevel.medium : DelayRiskLevel.low);
      factors.add(concern);
    }

    // ── Rule 7: Where the operating aircraft actually is ──
    // Only meaningful shortly before departure: an aircraft still far away an
    // hour out cannot make an on-time departure.
    final position = inboundPosition;
    if (position != null && flight.scheduleIsKnown) {
      final minutesToDeparture = flight.scheduledDeparture.difference(now ?? DateTime.now()).inMinutes;
      if (minutesToDeparture > 0 && minutesToDeparture <= 180) {
        if (position.airborne && position.distanceToDepartureKm > 0) {
          // Rough flying time at 780 km/h, plus 35 minutes to land and turn around.
          final neededMinutes = (position.distanceToDepartureKm / 780 * 60).round() + 35;
          if (neededMinutes > minutesToDeparture + 45) {
            highestRisk = _elevate(highestRisk, DelayRiskLevel.high);
            factors.add('Your aircraft is ${position.distanceToDepartureKm.round()} km away and needs about '
                '$neededMinutes min to arrive and turn around');
          } else if (neededMinutes > minutesToDeparture) {
            highestRisk = _elevate(highestRisk, DelayRiskLevel.medium);
            factors.add('Your aircraft is still ${position.distanceToDepartureKm.round()} km away — a tight turnaround');
          }
        }
      }
    }

    // ── Rule 5: Flight status alerts ──
    if (flight.status == FlightStatusEnum.cancelled) {
      highestRisk = DelayRiskLevel.high;
      factors.add('Flight has been cancelled');
    }
    if (flight.status == FlightStatusEnum.diverted) {
      highestRisk = DelayRiskLevel.high;
      factors.add('Flight has been diverted');
    }

    // ── Build result ──
    if (factors.isEmpty) {
      if (flight.status == FlightStatusEnum.scheduled ||
          flight.status == FlightStatusEnum.active) {
        return DelayRisk(
          level: DelayRiskLevel.low,
          explanation: 'On schedule — no delay indicators detected',
          factors: const ['No delay data from provider'],
          assessedAt: DateTime.now(),
        );
      }
      return DelayRisk(
        level: DelayRiskLevel.unknown,
        explanation: 'Delay risk unavailable — data pending',
        assessedAt: DateTime.now(),
      );
    }

    return DelayRisk(
      level: highestRisk,
      explanation: factors.first,
      factors: factors,
      assessedAt: DateTime.now(),
    );
  }

  DelayRiskLevel _elevate(DelayRiskLevel current, DelayRiskLevel candidate) {
    const order = [
      DelayRiskLevel.unknown,
      DelayRiskLevel.low,
      DelayRiskLevel.medium,
      DelayRiskLevel.high,
    ];
    return order.indexOf(candidate) > order.indexOf(current)
        ? candidate
        : current;
  }
}

/// Live position of the aircraft assigned to a flight, relative to that
/// flight's departure airport.
class InboundAircraftPosition {
  final bool airborne;
  final double distanceToDepartureKm;
  const InboundAircraftPosition({required this.airborne, required this.distanceToDepartureKm});
}
