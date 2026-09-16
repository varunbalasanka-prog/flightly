import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../blocs/flight/flight_bloc.dart';
import '../../blocs/flight_lookup/flight_lookup_bloc.dart';
import '../../models/models.dart';

/// Flight search screen — search live commercial flights.
/// Connects to OpenSky Network & Built-in Aviation Engine.
class FlightSearchScreen extends StatefulWidget {
  const FlightSearchScreen({super.key});

  @override
  State<FlightSearchScreen> createState() => _FlightSearchScreenState();
}

class _FlightSearchScreenState extends State<FlightSearchScreen> {
  final _searchController = TextEditingController();
  Flight? _selectedFlight;
  bool _isSaving = false;

  final List<String> _popularFlights = [
    'AA100',
    'DL123',
    'BA192',
    'EK201',
    '6E204',
    'UA888',
    'SQ321',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search([String? overrideQuery]) {
    final query = (overrideQuery ?? _searchController.text).trim().toUpperCase();
    if (query.isEmpty) return;

    if (overrideQuery != null) {
      _searchController.text = overrideQuery;
    }

    setState(() {
      _selectedFlight = null;
    });

    context.read<FlightLookupBloc>().add(FlightLookupRequested(query));
  }

  Future<void> _addFlight(Flight flight) async {
    // This used to fire the event and immediately claim success, so a failed
    // insert (quota, RLS, offline) still told the user the flight was tracked.
    setState(() => _isSaving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final cs = Theme.of(context).colorScheme;
    final bloc = context.read<FlightBloc>();

    try {
      await bloc.addFlight(flight);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${flight.flightNumber} added to your tracked flights'),
          backgroundColor: cs.primary,
          duration: const Duration(seconds: 2),
        ),
      );
      navigator.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't track ${flight.flightNumber}. Please try again."),
          backgroundColor: cs.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Flight'),
      ),
      body: BlocConsumer<FlightLookupBloc, FlightLookupState>(
        listener: (context, state) {
          if (state is FlightLookupSuccess && state.result.hasResults) {
            setState(() {
              _selectedFlight = state.result.flights.first;
            });
          }
        },
        builder: (context, state) {
          final isSearching = state is FlightLookupInProgress;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Search Input ──
                TextField(
                  controller: _searchController,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. AA100, DL123',
                    labelText: 'Flight Number',
                    prefixIcon: const Icon(Icons.flight),
                    suffixIcon: isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () => _search(),
                          ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),

                // ── Free Live Data Notice ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.radar, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Powered by OpenSky Network & SkyPulse Live Aviation Engine (Free)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Popular suggestions chips ──
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _popularFlights.map((f) {
                    return ActionChip(
                      label: Text(f, style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.flight_takeoff, size: 14),
                      onPressed: () => _search(f),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // ── Results or Placeholder ──
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildResultsArea(context, state, cs),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsArea(
      BuildContext context, FlightLookupState state, ColorScheme cs) {
    if (state is FlightLookupInProgress) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Searching live flight telemetry...',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (state is FlightLookupFailure) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(
                'Flight Not Found',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                state.error,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedFlight != null) {
      final flight = _selectedFlight!;
      final timeFmt = DateFormat('h:mm a');
      final dateFmt = DateFormat('EEE, MMM d');

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ADS-B tells us the route and whether the aircraft is flying;
              // it carries no timetable, gates or baggage belts. Say so rather
              // than leaving the blanks unexplained.
              if (!flight.scheduleIsKnown) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Route confirmed from live ADS-B. Departure times and '
                          'gates are not published by this source — add your own '
                          'times after tracking.',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Airline & Status row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.flight, color: cs.onPrimaryContainer, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            flight.flightNumber,
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            flight.airlineName ?? flight.airlineIata,
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: flight.status == FlightStatusEnum.active
                          ? Colors.green.withValues(alpha: 0.2)
                          : cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      flight.status.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: flight.status == FlightStatusEnum.active
                            ? Colors.greenAccent
                            : cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),

              // Route Display
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Departure
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          flight.departureAirportIata,
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          flight.departureAirportName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        // ADS-B sources give the route but no timetable, so
                        // showing the placeholder here would read as if the
                        // airline had published these times.
                        if (flight.scheduleIsKnown) ...[
                          Text(
                            timeFmt.format(flight.scheduledDeparture),
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            dateFmt.format(flight.scheduledDeparture),
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ] else
                          Text(
                            '--:--',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (flight.departureGate != null)
                          Text('Gate ${flight.departureGate}',
                              style: TextStyle(fontSize: 12, color: cs.primary)),
                      ],
                    ),
                  ),

                  // Flight Icon Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.arrow_forward_rounded, color: cs.primary, size: 28),
                  ),

                  // Arrival
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          flight.arrivalAirportIata,
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          flight.arrivalAirportName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        if (flight.scheduleIsKnown) ...[
                          Text(
                            timeFmt.format(flight.scheduledArrival),
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            dateFmt.format(flight.scheduledArrival),
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ] else
                          Text(
                            '--:--',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (flight.arrivalGate != null)
                          Text('Gate ${flight.arrivalGate}',
                              style: TextStyle(fontSize: 12, color: cs.primary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Aircraft & Baggage
              if (flight.aircraft != null || flight.baggageClaim != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (flight.aircraft != null)
                        Row(
                          children: [
                            Icon(Icons.airplanemode_active, size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              flight.aircraft!.modelName ?? 'Commercial Jet',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      if (flight.baggageClaim != null)
                        Row(
                          children: [
                            Icon(Icons.luggage, size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              flight.baggageClaim!,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Action Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : () => _addFlight(flight),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark_add),
                  label: Text(_isSaving ? 'Tracking Flight...' : 'Track & Add to My Flights'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default empty placeholder
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flight_takeoff_rounded,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Enter a flight number above',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try tapping one of the chips above (e.g. AA100, DL123)',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
