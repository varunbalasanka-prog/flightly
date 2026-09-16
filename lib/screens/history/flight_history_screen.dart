import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../blocs/flight/flight_bloc.dart';
import '../../models/models.dart';
import '../../services/aviation_data_service.dart';

/// Flight history: passport map, trip stats and past flights.
///
/// Everything here is derived from the user's own flights. This screen
/// previously rendered a fixed mockup — five invented flights, six invented
/// stat tiles and three hard-coded route lines — identically for every user,
/// and its year filter only changed which chip looked selected.
class FlightHistoryScreen extends StatefulWidget {
  const FlightHistoryScreen({super.key});

  @override
  State<FlightHistoryScreen> createState() => _FlightHistoryScreenState();
}

class _FlightHistoryScreenState extends State<FlightHistoryScreen> {
  /// Selected year, or null for all time.
  int? _selectedYear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Flight History')),
      body: BlocBuilder<FlightBloc, FlightState>(
        builder: (context, state) {
          if (state is FlightLoadInProgress) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = state is FlightLoadSuccess
              ? state.flights.where((f) => f.status.isTerminal).toList()
              : const <Flight>[];

          if (all.isEmpty) {
            return _EmptyHistory(cs: cs);
          }

          final years = _availableYears(all);
          final flights = (_selectedYear == null
              ? List<Flight>.from(all)
              : all
                  .where((f) => f.scheduledDeparture.year == _selectedYear)
                  .toList())
            ..sort(
              (a, b) => b.scheduledDeparture.compareTo(a.scheduledDeparture),
            );

          final stats = _Stats.from(flights);

          return CustomScrollView(
            slivers: [
              if (years.length > 1)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: years.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final year = i == 0 ? null : years[i - 1];
                        final selected = _selectedYear == year;
                        return ChoiceChip(
                          label: Text(year?.toString() ?? 'ALL'),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedYear = year),
                          selectedColor: cs.primary.withValues(alpha: 0.2),
                          labelStyle: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected ? cs.primary : cs.onSurfaceVariant,
                          ),
                          showCheckmark: false,
                          side: BorderSide(
                            color: selected
                                ? cs.primary.withValues(alpha: 0.3)
                                : cs.outlineVariant.withValues(alpha: 0.3),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // ── Passport map of routes actually flown ──
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FlutterMap(
                    options: const MapOptions(
                      initialCenter: LatLng(30, -30),
                      initialZoom: 2.0,
                      interactionOptions:
                          InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: isDark
                            ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                            : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.skypulse.skypulse',
                      ),
                      PolylineLayer(
                        polylines: _routeLines(flights, cs.secondary),
                      ),
                      // Required by the OpenStreetMap and CARTO basemap terms.
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                          TextSourceAttribution('CARTO'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Stats computed from the flights above ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _StatTile(
                        value: _compact(stats.distanceKm),
                        label: 'km',
                        cs: cs,
                      ),
                      const SizedBox(width: 8),
                      _StatTile(
                        value: '${stats.flightCount}',
                        label: 'Flights',
                        cs: cs,
                      ),
                      const SizedBox(width: 8),
                      _StatTile(
                        value: '${stats.airports}',
                        label: 'Airports',
                        cs: cs,
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _StatTile(
                        value: '${stats.airlines}',
                        label: 'Airlines',
                        cs: cs,
                      ),
                      const SizedBox(width: 8),
                      _StatTile(
                        value: stats.airtimeLabel,
                        label: 'Airtime',
                        cs: cs,
                      ),
                      const SizedBox(width: 8),
                      _StatTile(
                        value: stats.delayedLabel,
                        label: 'Delayed',
                        cs: cs,
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text(
                    'PAST FLIGHTS',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),

              SliverList.builder(
                itemCount: flights.length,
                itemBuilder: (context, index) =>
                    _FlightRow(flight: flights[index], cs: cs),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }

  List<int> _availableYears(List<Flight> flights) {
    return flights.map((f) => f.scheduledDeparture.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
  }

  /// One line per distinct route actually flown.
  List<Polyline> _routeLines(List<Flight> flights, Color color) {
    final seen = <String>{};
    final lines = <Polyline>[];

    for (final f in flights) {
      final key = '${f.departureAirportIata}-${f.arrivalAirportIata}';
      if (!seen.add(key)) continue;

      final from = AviationDataService.airports[f.departureAirportIata];
      final to = AviationDataService.airports[f.arrivalAirportIata];
      if (from == null || to == null) continue;

      lines.add(Polyline(
        points: [LatLng(from.lat, from.lng), LatLng(to.lat, to.lng)],
        color: color.withValues(alpha: 0.6),
        strokeWidth: 1.5,
      ));
    }
    return lines;
  }

  static String _compact(double value) {
    if (value >= 1000) {
      return NumberFormat.decimalPattern().format(value.round());
    }
    return value.round().toString();
  }
}

/// Aggregate figures computed from the user's own flight list.
class _Stats {
  final double distanceKm;
  final int flightCount;
  final int airports;
  final int airlines;
  final Duration airtime;
  final int delayedCount;

  const _Stats({
    required this.distanceKm,
    required this.flightCount,
    required this.airports,
    required this.airlines,
    required this.airtime,
    required this.delayedCount,
  });

  factory _Stats.from(List<Flight> flights) {
    var distance = 0.0;
    var airtime = Duration.zero;
    var delayed = 0;
    final airports = <String>{};
    final airlines = <String>{};

    for (final f in flights) {
      airports
        ..add(f.departureAirportIata)
        ..add(f.arrivalAirportIata);
      if (f.airlineIata.isNotEmpty) airlines.add(f.airlineIata);
      if (f.isDelayed) delayed++;

      final leg = f.bestArrivalTime.difference(f.bestDepartureTime);
      if (!leg.isNegative) airtime += leg;

      final from = AviationDataService.airports[f.departureAirportIata];
      final to = AviationDataService.airports[f.arrivalAirportIata];
      if (from != null && to != null) {
        distance += AviationDataService.instance
            .distanceKm(from.lat, from.lng, to.lat, to.lng);
      }
    }

    return _Stats(
      distanceKm: distance,
      flightCount: flights.length,
      airports: airports.length,
      airlines: airlines.length,
      airtime: airtime,
      delayedCount: delayed,
    );
  }

  String get airtimeLabel => '${airtime.inHours}h';

  String get delayedLabel {
    if (flightCount == 0) return '0%';
    return '${((delayedCount / flightCount) * 100).round()}%';
  }
}

class _FlightRow extends StatelessWidget {
  final Flight flight;
  final ColorScheme cs;
  const _FlightRow({required this.flight, required this.cs});

  @override
  Widget build(BuildContext context) {
    final cancelled = flight.status == FlightStatusEnum.cancelled;
    final label = cancelled
        ? 'Cancelled'
        : flight.isDelayed
            ? 'Delayed'
            : 'On Time';
    final bad = cancelled || flight.isDelayed;

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.flight, color: cs.secondary, size: 20),
        title: Text(
          '${flight.flightNumber}  ${flight.routeDisplay}',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          DateFormat.MMMd().format(flight.scheduledDeparture),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: bad
                ? cs.error.withValues(alpha: 0.15)
                : cs.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: bad ? cs.error : cs.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyHistory({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No flights yet',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completed flights appear here with your route map and stats.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final ColorScheme cs;
  const _StatTile({required this.value, required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
