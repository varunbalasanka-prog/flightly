import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../blocs/flight/flight_bloc.dart';
import '../../blocs/trip/trip_bloc.dart';
import '../../models/models.dart';

/// Upcoming trips & tracked flights screen — the main "Home" tab.
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Trips & Flights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<FlightBloc>().add(FlightLoadRequested());
              context.read<TripBloc>().add(TripLoadRequested());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<FlightBloc>().add(FlightLoadRequested());
          context.read<TripBloc>().add(TripLoadRequested());
        },
        child: CustomScrollView(
          slivers: [
            // ── Search Bar ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: GestureDetector(
                  onTap: () => context.push('/flight/search'),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Search to add flights (e.g. AA100, DL123)',
                          style: GoogleFonts.inter(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Active Flight Banner ──
            SliverToBoxAdapter(
              child: BlocBuilder<FlightBloc, FlightState>(
                builder: (context, state) {
                  Flight? activeFlight;
                  if (state is FlightLoadSuccess && state.flights.isNotEmpty) {
                    activeFlight = state.flights.firstWhere(
                      (f) => f.status == FlightStatusEnum.active,
                      orElse: () => state.flights.first,
                    );
                  }
                  return _ActiveFlightBanner(cs: cs, flight: activeFlight);
                },
              ),
            ),

            // ── Section Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TRACKED FLIGHTS',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.5,
                      ),
                    ),
                    BlocBuilder<FlightBloc, FlightState>(
                      builder: (context, state) {
                        if (state is FlightLoadSuccess) {
                          return Text(
                            '${state.flights.length} flights',
                            style: TextStyle(fontSize: 12, color: cs.primary),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Flight Cards List ──
            BlocBuilder<FlightBloc, FlightState>(
              builder: (context, state) {
                if (state is FlightLoadInProgress) {
                  return const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  );
                }

                if (state is FlightLoadSuccess) {
                  if (state.flights.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.flight_outlined, size: 48, color: cs.primary.withValues(alpha: 0.7)),
                              const SizedBox(height: 12),
                              Text(
                                'No tracked flights yet',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Search for your upcoming flight number or add one manually to start tracking live gates, delays, and telemetry.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => context.push('/flight/search'),
                                icon: const Icon(Icons.search),
                                label: const Text('Search Flights'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final flight = state.flights[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: _FlightCard(flight: flight, cs: cs),
                        );
                      },
                      childCount: state.flights.length,
                    ),
                  );
                }

                return const SliverToBoxAdapter(child: SizedBox.shrink());
              },
            ),

            // ── Bottom padding ──
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Flight'),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.search, color: cs.primary),
              title: const Text('Search Flight'),
              subtitle: const Text('Instant lookup by flight number (AA100, DL123)'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/flight/search');
              },
            ),
            ListTile(
              leading: Icon(Icons.edit_note, color: cs.secondary),
              title: const Text('Add Manually'),
              subtitle: const Text('Enter custom flight details'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/flight/manual');
              },
            ),
            ListTile(
              leading: Icon(Icons.folder_open, color: cs.tertiary),
              title: const Text('Create New Trip'),
              subtitle: const Text('Group flights into a travel itinerary'),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateTripDialog(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreateTripDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Trip'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. Paris Summer Vacation',
            labelText: 'Trip Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<TripBloc>().add(TripCreateRequested(name));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Trip "$name" created!')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ActiveFlightBanner extends StatelessWidget {
  final ColorScheme cs;
  final Flight? flight;
  const _ActiveFlightBanner({required this.cs, this.flight});

  @override
  Widget build(BuildContext context) {
    final hasFlight = flight != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          if (hasFlight) {
            context.push('/flight/${flight!.id}');
          } else {
            context.push('/flight/search');
          }
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.15),
                cs.primary.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: hasFlight ? Colors.greenAccent : cs.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (hasFlight ? Colors.greenAccent : cs.primary).withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasFlight ? '${flight!.flightNumber} · ${flight!.routeDisplay}' : 'No active flights right now',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasFlight
                            ? 'Status: ${flight!.status.name.toUpperCase()} · ${flight!.departureAirportIata} → ${flight!.arrivalAirportIata}'
                            : 'Tap to search and track a live flight',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.primary, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlightCard extends StatelessWidget {
  final Flight flight;
  final ColorScheme cs;
  const _FlightCard({required this.flight, required this.cs});

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');
    final dateFmt = DateFormat('EEE, MMM d');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/flight/${flight.id}', extra: flight),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Airline, Flight number, Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.flight, color: cs.primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        flight.flightNumber,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        flight.airlineName ?? flight.airlineIata,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: flight.status == FlightStatusEnum.active
                          ? Colors.green.withValues(alpha: 0.2)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      flight.status.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: flight.status == FlightStatusEnum.active
                            ? Colors.greenAccent
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Route & Times
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        flight.departureAirportIata,
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        timeFmt.format(flight.scheduledDeparture),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        dateFmt.format(flight.scheduledDeparture),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (flight.departureGate != null)
                        Text('Gate ${flight.departureGate}',
                            style: TextStyle(fontSize: 11, color: cs.primary)),
                    ],
                  ),

                  // Flight route line icon
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_forward, size: 16, color: cs.primary),
                          ),
                          Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                  ),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        flight.arrivalAirportIata,
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        timeFmt.format(flight.scheduledArrival),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        dateFmt.format(flight.scheduledArrival),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (flight.arrivalGate != null)
                        Text('Gate ${flight.arrivalGate}',
                            style: TextStyle(fontSize: 11, color: cs.primary)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
