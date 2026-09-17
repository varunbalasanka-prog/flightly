import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../blocs/flight/flight_bloc.dart';
import '../../blocs/sharing/sharing_bloc.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../services/airport_directory.dart';
import '../../services/weather_service.dart';
import '../../services/world_traffic_service.dart';
import '../../utils/delay_risk_calculator.dart';
import '../destination/destination_panel.dart';
import 'flight_extras.dart';

/// Flight detail screen — the core screen of SkyPulse.
/// Displays live flight status, gate changes, delay analysis, aircraft specs,
/// route telemetry, and sharing actions.
class FlightDetailScreen extends StatelessWidget {
  final String flightId;
  final Flight? initialFlight;

  const FlightDetailScreen({
    super.key,
    required this.flightId,
    this.initialFlight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocBuilder<FlightBloc, FlightState>(
      builder: (context, state) {
        Flight? flight = initialFlight;

        if (state is FlightLoadSuccess) {
          final found = state.flights.where((f) => f.id == flightId);
          if (found.isNotEmpty) {
            flight = found.first;
          }
        }

        // This used to fall back to a hard-coded "AA 472 DFW → DCA" with a
        // gate, terminal and delay, so an unknown id rendered a fake flight.
        if (flight == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: state is FlightLoadInProgress || state is FlightInitial
                  ? const CircularProgressIndicator()
                  : Text(
                      'This flight is no longer in your list.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
            ),
          );
        }

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              // ── Status App Bar ──
              SliverAppBar(
                expandedHeight: 56,
                pinned: true,
                title: Text(flight.flightNumber),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Share Flight',
                    onPressed: () => _showShareDialog(context, flight!),
                  ),
                  IconButton(
                    icon: const Icon(Icons.map_outlined),
                    tooltip: 'Live Map',
                    onPressed: () =>
                        context.push('/flight/$flightId/map', extra: flight),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (val) {
                      if (val == 'delete') {
                        _confirmDelete(context, flight!);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Untrack Flight',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // ── Status Banner ──
              SliverToBoxAdapter(
                child: _StatusBanner(flight: flight, cs: cs),
              ),

              // ── Route Header ──
              SliverToBoxAdapter(
                child: _RouteHeader(flight: flight, cs: cs),
              ),

              // ── Times Card ──
              SliverToBoxAdapter(
                child: _TimesCard(flight: flight, cs: cs),
              ),

              // ── Gate & Terminal Info ──
              SliverToBoxAdapter(
                child: _GateCard(flight: flight, cs: cs),
              ),

              SliverToBoxAdapter(child: FlightActionsRow(flight: flight)),

              // ── Delay Risk Card ──
              SliverToBoxAdapter(
                child: _DelayRiskCard(flight: flight, cs: cs),
              ),

              SliverToBoxAdapter(child: WhereIsMyPlaneCard(flight: flight)),
              SliverToBoxAdapter(child: LeaveForAirportCard(flight: flight)),

              // ── Timeline ──
              SliverToBoxAdapter(
                child: _TimelineSection(flight: flight, cs: cs),
              ),

              // ── Aircraft Info ──
              if (flight.aircraft != null)
                SliverToBoxAdapter(
                  child: _AircraftCard(aircraft: flight.aircraft!, cs: cs),
                ),

              // ── Destination: weather, radio, cameras, news ──
              SliverToBoxAdapter(child: DestinationPanel(flight: flight)),

              // ── Data Freshness Footer ──
              SliverToBoxAdapter(
                child: _DataFreshnessBadge(
                  dataSource: flight.dataSource ?? 'SkyPulse Realtime',
                  lastUpdated: flight.lastUpdated ?? DateTime.now(),
                  cs: cs,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
        );
      },
    );
  }

  void _showShareDialog(BuildContext context, Flight flight) {
    context.read<SharingBloc>().add(ShareCodeRequested(flight.id));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return BlocBuilder<SharingBloc, SharingState>(
          builder: (context, shareState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Share ${flight.flightNumber}',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Friends can use this invite code in the Friends tab to track this flight in real time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (shareState is SharingInProgress)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    else if (shareState is ShareCodeSuccess) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          shareState.code,
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: shareState.code),
                          );
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text('Invite code copied to clipboard!'),
                            ),
                          );
                          Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy Invite Code'),
                      ),
                    ] else if (shareState is SharingFailure) ...[
                      Text(
                        'Error: ${shareState.error}',
                        style: TextStyle(color: cs.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Flight flight) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Untrack ${flight.flightNumber}?'),
        content: const Text(
          'This will remove this flight and cancel all background telemetry and push alerts for it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<FlightBloc>().add(FlightDeleteRequested(flight.id));
              context.pop();
            },
            child: const Text('Untrack'),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Flight flight;
  final ColorScheme cs;
  const _StatusBanner({required this.flight, required this.cs});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String text;

    switch (flight.status) {
      case FlightStatusEnum.active:
        bgColor = cs.primary.withValues(alpha: 0.15);
        textColor = cs.primary;
        icon = Icons.flight_takeoff;
        text = 'In Flight · Cruising';
      case FlightStatusEnum.landed:
        bgColor = Colors.green.withValues(alpha: 0.15);
        textColor = Colors.green;
        icon = Icons.flight_land;
        text = 'Landed Safely';
      case FlightStatusEnum.cancelled:
        bgColor = cs.error.withValues(alpha: 0.15);
        textColor = cs.error;
        icon = Icons.cancel_outlined;
        text = 'Flight Cancelled';
      case FlightStatusEnum.diverted:
        bgColor = cs.error.withValues(alpha: 0.15);
        textColor = cs.error;
        icon = Icons.alt_route;
        text = 'Diverted';
      default:
        if (flight.isDelayed) {
          bgColor = SkyPulseTheme.warningColor(context).withValues(alpha: 0.15);
          textColor = SkyPulseTheme.warningColor(context);
          icon = Icons.schedule;
          text = 'Delayed ${flight.departureDelayMinutes ?? 0}m';
        } else {
          bgColor = cs.primary.withValues(alpha: 0.12);
          textColor = cs.primary;
          icon = Icons.check_circle_outline;
          text = 'On Time · Scheduled';
        }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: textColor),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteHeader extends StatelessWidget {
  final Flight flight;
  final ColorScheme cs;
  const _RouteHeader({required this.flight, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _AirportColumn(
            iata: flight.departureAirportIata,
            name: flight.departureAirportName ?? '',
            alignment: CrossAxisAlignment.start,
            cs: cs,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.flight, color: cs.secondary, size: 24),
                  const SizedBox(height: 6),
                  Container(
                    height: 1.5,
                    color: cs.secondary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    flight.airlineName ?? flight.airlineIata,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          _AirportColumn(
            iata: flight.arrivalAirportIata,
            name: flight.arrivalAirportName ?? '',
            alignment: CrossAxisAlignment.end,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

class _AirportColumn extends StatelessWidget {
  final String iata;
  final String name;
  final CrossAxisAlignment alignment;
  final ColorScheme cs;
  const _AirportColumn({
    required this.iata,
    required this.name,
    required this.alignment,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    // Tap an airport code for its live conditions, traffic, cameras and radio.
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/airport/$iata'),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            iata,
            style: GoogleFonts.inter(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              letterSpacing: 1,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: alignment == CrossAxisAlignment.start
                  ? TextAlign.left
                  : TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimesCard extends StatelessWidget {
  final Flight flight;
  final ColorScheme cs;
  const _TimesCard({required this.flight, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _TimeColumn(
                label: 'DEPARTURE',
                scheduled: flight.scheduledDeparture,
                estimated: flight.estimatedDeparture,
                actual: flight.actualDeparture,
                delay: flight.departureDelayMinutes,
                cs: cs,
              ),
            ),
            Container(
              width: 1,
              height: 60,
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: _TimeColumn(
                label: 'ARRIVAL',
                scheduled: flight.scheduledArrival,
                estimated: flight.estimatedArrival,
                actual: flight.actualArrival,
                delay: flight.arrivalDelayMinutes,
                cs: cs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  final String label;
  final DateTime scheduled;
  final DateTime? estimated;
  final DateTime? actual;
  final int? delay;
  final ColorScheme cs;

  const _TimeColumn({
    required this.label,
    required this.scheduled,
    this.estimated,
    this.actual,
    this.delay,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final bestTime = actual ?? estimated ?? scheduled;
    final isDelayed = delay != null && delay! > 0;
    final timeColor = isDelayed
        ? SkyPulseTheme.warningColor(context)
        : cs.onSurface;

    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _formatTime(bestTime),
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: timeColor,
          ),
        ),
        if (isDelayed) ...[
          const SizedBox(height: 2),
          Text(
            'Sched: ${_formatTime(scheduled)}',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _GateCard extends StatelessWidget {
  final Flight flight;
  final ColorScheme cs;
  const _GateCard({required this.flight, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _GateBadge(
              label: 'DEPARTURE GATE',
              value: flight.departureGate ?? 'TBD',
              terminal: flight.departureTerminal,
              cs: cs,
            ),
            const SizedBox(width: 12),
            _GateBadge(
              label: 'ARRIVAL GATE',
              value: flight.arrivalGate ?? 'TBD',
              terminal: flight.arrivalTerminal,
              cs: cs,
            ),
            if (flight.baggageClaim != null) ...[
              const SizedBox(width: 12),
              _GateBadge(
                label: 'BAGGAGE',
                value: flight.baggageClaim!,
                terminal: null,
                cs: cs,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GateBadge extends StatelessWidget {
  final String label;
  final String value;
  final String? terminal;
  final ColorScheme cs;

  const _GateBadge({
    required this.label,
    required this.value,
    this.terminal,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            if (terminal != null) ...[
              const SizedBox(height: 2),
              Text(
                'Terminal $terminal',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DelayRiskCard extends StatefulWidget {
  final Flight flight;
  final ColorScheme cs;
  const _DelayRiskCard({required this.flight, required this.cs});

  @override
  State<_DelayRiskCard> createState() => _DelayRiskCardState();
}

class _DelayRiskCardState extends State<_DelayRiskCard> {
  List<String> _weatherConcerns = const [];
  InboundAircraftPosition? _inbound;

  Flight get flight => widget.flight;
  ColorScheme get cs => widget.cs;

  @override
  void initState() {
    super.initState();
    _loadSignals();
  }

  @override
  void didUpdateWidget(covariant _DelayRiskCard old) {
    super.didUpdateWidget(old);
    if (old.flight.aircraftRegistration != flight.aircraftRegistration) {
      _loadSignals();
    }
  }

  /// Observed weather at both airports and, when the tail number is known,
  /// where the operating aircraft is right now.
  Future<void> _loadSignals() async {
    final dep = await AirportDirectory.instance.lookup(
      flight.departureAirportIata,
    );
    final arr = await AirportDirectory.instance.lookup(
      flight.arrivalAirportIata,
    );
    final metars = await WeatherService.instance.metars([
      ?dep?.icao,
      ?arr?.icao,
    ]);
    final concerns = [for (final m in metars.values) ...m.operationalConcerns];

    InboundAircraftPosition? inbound;
    final reg = flight.aircraftRegistration;
    if (reg != null && reg.isNotEmpty && dep != null) {
      final aircraft = await WorldTrafficService.instance.byRegistration(reg);
      if (aircraft != null) {
        inbound = InboundAircraftPosition(
          airborne: !aircraft.onGround,
          distanceToDepartureKm: haversineKm(
            aircraft.lat,
            aircraft.lon,
            dep.lat,
            dep.lon,
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _weatherConcerns = concerns;
      _inbound = inbound;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This was an inline `delay > 30` branch presented as "Predictive Delay
    // Risk", with copy about airspace and ground flow that nothing here
    // measured. DelayRiskCalculator was already written and unit-tested but
    // had no caller; it applies explicit rules and returns the factors behind
    // its verdict, so the card can show its working.
    final risk = const DelayRiskCalculator().calculate(
      flight: flight,
      weatherConcerns: _weatherConcerns,
      inboundPosition: _inbound,
    );

    final riskLevel = risk.level.displayName;
    final riskColor = switch (risk.level) {
      DelayRiskLevel.high => Colors.redAccent,
      DelayRiskLevel.medium => Colors.amber,
      DelayRiskLevel.low => Colors.green,
      DelayRiskLevel.unknown => cs.onSurfaceVariant,
    };
    final description = risk.explanation;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, size: 18, color: cs.secondary),
                const SizedBox(width: 8),
                Text(
                  // Nothing here predicts; it applies stated rules.
                  'Delay Risk',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    riskLevel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: riskColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            // Show every rule that fired, so the verdict is auditable rather
            // than a bare label.
            if (risk.factors.length > 1) ...[
              const SizedBox(height: 10),
              ...risk.factors
                  .skip(1)
                  .map(
                    (factor) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5, right: 8),
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: cs.onSurfaceVariant,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              factor,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimelineSection extends StatelessWidget {
  final Flight flight;
  final ColorScheme cs;
  const _TimelineSection({required this.flight, required this.cs});

  @override
  Widget build(BuildContext context) {
    final events = [
      // "Gate assigned" at T-60 and "Boarding" at T-35 were invented offsets
      // presented as events. Only times the flight actually carries are shown.
      (
        'Departure (${flight.departureAirportIata})',
        flight.bestDepartureTime,
        Icons.flight_takeoff,
        flight.status == FlightStatusEnum.active ||
            flight.status == FlightStatusEnum.landed,
      ),
      (
        'Arrival (${flight.arrivalAirportIata})',
        flight.bestArrivalTime,
        Icons.flight_land,
        flight.status == FlightStatusEnum.landed,
      ),
    ];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Flight Timeline',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ...events.map(
              (e) => _TimelineEvent(
                label: e.$1,
                time: e.$2,
                icon: e.$3,
                isCompleted: e.$4,
                cs: cs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  final String label;
  final DateTime time;
  final IconData icon;
  final bool isCompleted;
  final ColorScheme cs;

  const _TimelineEvent({
    required this.label,
    required this.time,
    required this.icon,
    required this.isCompleted,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isCompleted
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 14,
              color: isCompleted ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
            ),
          ),
          Text(
            '$h:$m',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AircraftCard extends StatelessWidget {
  final Aircraft aircraft;
  final ColorScheme cs;
  const _AircraftCard({required this.aircraft, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.airplanemode_active,
                size: 22,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  aircraft.modelName ?? 'Aircraft Telemetry Active',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reg: ${aircraft.registration ?? "N/A"} · ICAO: ${aircraft.icaoCode ?? "N/A"}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DataFreshnessBadge extends StatelessWidget {
  final String dataSource;
  final DateTime lastUpdated;
  final ColorScheme cs;

  const _DataFreshnessBadge({
    required this.dataSource,
    required this.lastUpdated,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(lastUpdated);
    final ageText = age.inMinutes < 1
        ? 'Just now'
        : age.inMinutes < 60
        ? '${age.inMinutes}m ago'
        : '${age.inHours}h ago';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sensors, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            'Live telemetry: $dataSource · Synced $ageText',
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
