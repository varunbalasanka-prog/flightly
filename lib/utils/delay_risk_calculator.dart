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
