import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Connection guidance between two flights.
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Connection Status ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.connecting_airports, size: 40, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Connection Safe',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '2h 15min layover at DCA',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Inbound Flight ──
            _FlightTile(
              label: 'ARRIVING',
              flightNumber: 'AA 472',
              route: 'DFW → DCA',
              time: '14:20',
              status: 'On Time',
              statusColor: cs.primary,
              cs: cs,
            ),
            const SizedBox(height: 12),

            // ── Outbound Flight ──
            _FlightTile(
              label: 'DEPARTING',
              flightNumber: 'UA 348',
              route: 'DCA → BOS',
              time: '16:35',
              status: 'On Time',
              statusColor: cs.primary,
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }
}

class _FlightTile extends StatelessWidget {
  final String label;
  final String flightNumber;
  final String route;
  final String time;
  final String status;
  final Color statusColor;
  final ColorScheme cs;

  const _FlightTile({
    required this.label,
    required this.flightNumber,
    required this.route,
    required this.time,
    required this.status,
    required this.statusColor,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
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
                  flightNumber,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(route,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const Spacer(),
                Text(time,
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status,
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
