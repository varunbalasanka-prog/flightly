import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../blocs/flight/flight_bloc.dart';
import '../../models/models.dart';
import '../../utils/connection_calculator.dart';

/// Connection guidance between two of the user's flights.
///
/// This screen took an inbound and outbound flight id and ignored both,
/// rendering a fixed "Connection Safe · 2h 15min layover at DCA · AA 472 ·
/// UA 348" for every input. It now resolves the real flights and runs
/// [ConnectionCalculator], which was written and unit-tested but had no caller.
class ConnectionScreen extends StatelessWidget {
  final String inboundFlightId;
  final String outboundFlightId;

  const ConnectionScreen({
    super.key,
    required this.inboundFlightId,
    required this.outboundFlightId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Connection')),
      body: BlocBuilder<FlightBloc, FlightState>(
        builder: (context, state) {
          if (state is FlightLoadInProgress) {
            return const Center(child: CircularProgressIndicator());
          }

          final flights =
              state is FlightLoadSuccess ? state.flights : const <Flight>[];

          final inbound = _findById(flights, inboundFlightId);
          final outbound = _findById(flights, outboundFlightId);

          if (inbound == null || outbound == null) {
            return _Message(
              icon: Icons.connecting_airports_outlined,
              title: 'Connection unavailable',
              body: 'One of these flights is no longer in your list.',
              cs: cs,
            );
          }

          final connection = const ConnectionCalculator().calculate(
            inboundFlight: inbound,
            outboundFlight: outbound,
          );

          final accent = _statusColor(connection.status, cs);
          final timeFmt = DateFormat('HH:mm');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Verdict ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(_statusIcon(connection.status), size: 40, color: accent),
                    const SizedBox(height: 12),
                    Text(
                      'Connection ${connection.status.displayName}',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      connection.explanation,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (connection.connectionMinutes > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        _formatLayover(connection.connectionMinutes),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _FlightTile(
                label: 'ARRIVING',
                flight: inbound,
                time: timeFmt.format(inbound.bestArrivalTime),
                cs: cs,
              ),
              const SizedBox(height: 12),
              _FlightTile(
                label: 'DEPARTING',
                flight: outbound,
                time: timeFmt.format(outbound.bestDepartureTime),
                cs: cs,
              ),

              if (!connection.isSameAirport) ...[
                const SizedBox(height: 16),
                _Note(
                  text: 'These flights use different airports. You will need to '
                      'transfer between ${inbound.arrivalAirportIata} and '
                      '${outbound.departureAirportIata} yourself.',
                  cs: cs,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Flight? _findById(List<Flight> flights, String id) {
    for (final flight in flights) {
      if (flight.id == id) return flight;
    }
    return null;
  }

  static String _formatLayover(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}min layover';
    if (mins == 0) return '${hours}h layover';
    return '${hours}h ${mins}min layover';
  }

  static Color _statusColor(ConnectionStatusEnum status, ColorScheme cs) {
    switch (status) {
      case ConnectionStatusEnum.safe:
        return cs.primary;
      case ConnectionStatusEnum.tight:
        return Colors.amber;
      case ConnectionStatusEnum.atRisk:
      case ConnectionStatusEnum.missed:
        return cs.error;
    }
  }

  static IconData _statusIcon(ConnectionStatusEnum status) {
    switch (status) {
      case ConnectionStatusEnum.safe:
        return Icons.connecting_airports;
      case ConnectionStatusEnum.tight:
        return Icons.timer_outlined;
      case ConnectionStatusEnum.atRisk:
        return Icons.warning_amber_rounded;
      case ConnectionStatusEnum.missed:
        return Icons.error_outline;
    }
  }
}

class _FlightTile extends StatelessWidget {
  final String label;
  final Flight flight;
  final String time;
  final ColorScheme cs;

  const _FlightTile({
    required this.label,
    required this.flight,
    required this.time,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final delayed = flight.isDelayed;
    final cancelled = flight.status == FlightStatusEnum.cancelled;
    final statusLabel = cancelled
        ? 'Cancelled'
        : delayed
            ? 'Delayed'
            : flight.status.displayName;
    final statusColor =
        cancelled || delayed ? cs.error : cs.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Row(
              children: [
                Text(
                  flight.flightNumber,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    flight.routeDisplay,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ),
                const Spacer(),
                Text(
                  time,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
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

class _Note extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _Note({required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final ColorScheme cs;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
