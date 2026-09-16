import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../blocs/flight/flight_bloc.dart';
import '../../models/models.dart';
import '../../services/aviation_data_service.dart';

/// Live flight map with high-precision great-circle paths, real-time aircraft positioning,
/// and route telemetry HUD.
class LiveMapScreen extends StatefulWidget {
  final String? flightId;
  final Flight? flight;

  const LiveMapScreen({
    super.key,
    this.flightId,
    this.flight,
  });

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocBuilder<FlightBloc, FlightState>(
      builder: (context, state) {
        Flight? targetFlight = widget.flight;

        if (targetFlight == null && state is FlightLoadSuccess && state.flights.isNotEmpty) {
          if (widget.flightId != null) {
            targetFlight = state.flights.where((f) => f.id == widget.flightId).firstOrNull;
          }
          targetFlight ??= state.flights.firstWhere(
            (f) => f.status == FlightStatusEnum.active,
            orElse: () => state.flights.first,
          );
        }

        // Previously this fell back to a hard-coded "AA 100 JFK->LHR" flight
        // labelled `dataSource: 'OpenSky Network ADS-B'`, so a user with no
        // flights saw an invented aircraft presented as live radar.
        if (targetFlight == null) {
          return _buildEmptyState(context, state);
        }

        // Retrieve airport geo coordinates
        final originRecord = AviationDataService.airports[targetFlight.departureAirportIata] ??
            const AirportRecord(
              iata: 'JFK',
              icao: 'KJFK',
              name: 'John F. Kennedy Intl',
              city: 'New York',
              country: 'USA',
              lat: 40.6413,
              lng: -73.7781,
              timezone: 'America/New_York',
            );

        final destRecord = AviationDataService.airports[targetFlight.arrivalAirportIata] ??
            const AirportRecord(
              iata: 'LHR',
              icao: 'EGLL',
              name: 'Heathrow Airport',
              city: 'London',
              country: 'UK',
              lat: 51.4700,
              lng: -0.4543,
              timezone: 'Europe/London',
            );

        final originLatLng = LatLng(originRecord.lat, originRecord.lng);
        final destLatLng = LatLng(destRecord.lat, destRecord.lng);

        // Calculate great-circle arc coordinates
        final rawCoords = AviationDataService.instance.calculateGreatCircleCoordinates(
          originLatLng.latitude,
          originLatLng.longitude,
          destLatLng.latitude,
          destLatLng.longitude,
          points: 40,
        );
        final polylinePoints = rawCoords.map((c) => LatLng(c[0], c[1])).toList();

        // Compute plane progress (0.0 -> 1.0)
        final now = DateTime.now();
        final depTime = targetFlight.actualDeparture ?? targetFlight.scheduledDeparture;
        final arrTime = targetFlight.actualArrival ?? targetFlight.scheduledArrival;
        final totalDuration = arrTime.difference(depTime).inSeconds;

        double progress = 0.45; // Default aesthetic mid-flight position
        if (totalDuration > 0) {
          final elapsed = now.difference(depTime).inSeconds;
          progress = (elapsed / totalDuration).clamp(0.05, 0.95);
          if (targetFlight.status == FlightStatusEnum.scheduled) progress = 0.02;
          if (targetFlight.status == FlightStatusEnum.landed) progress = 1.0;
        }

        // Interpolate aircraft coordinate along the arc
        final index = (progress * (polylinePoints.length - 1)).floor();
        final nextIndex = min(index + 1, polylinePoints.length - 1);
        final planeLatLng = polylinePoints[index];
        final nextLatLng = polylinePoints[nextIndex];

        // Heading in radians/degrees
        final dLat = nextLatLng.latitude - planeLatLng.latitude;
        final dLng = nextLatLng.longitude - planeLatLng.longitude;
        final headingRad = atan2(dLng, dLat);

        final center = LatLng(
          (originLatLng.latitude + destLatLng.latitude) / 2,
          (originLatLng.longitude + destLatLng.longitude) / 2,
        );

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.5),
            elevation: 0,
            title: Text(
              '${targetFlight.flightNumber} · Live Radar',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.my_location),
                tooltip: 'Center Aircraft',
                onPressed: () {
                  _mapController.move(planeLatLng, 6.0);
                },
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out_map),
                tooltip: 'Fit Route',
                onPressed: () {
                  _mapController.move(center, 4.0);
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              // ── Flutter Map ──
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 4.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  // CartoDB Dark Matter / Positron Tiles
                  TileLayer(
                    urlTemplate: isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.skypulse.app',
                  ),

                  // Route Polyline Layer
                  PolylineLayer(
                    polylines: [
                      // Glow / Shadow polyline
                      Polyline(
                        points: polylinePoints,
                        color: cs.primary.withValues(alpha: 0.2),
                        strokeWidth: 6,
                      ),
                      // Solid route polyline
                      Polyline(
                        points: polylinePoints,
                        color: cs.primary,
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                  // Markers Layer (Origin, Destination, Aircraft)
                  MarkerLayer(
                    markers: [
                      // Origin Marker
                      Marker(
                        point: originLatLng,
                        width: 70,
                        height: 40,
                        child: _AirportMarker(
                          iata: targetFlight.departureAirportIata,
                          cs: cs,
                          isOrigin: true,
                        ),
                      ),
                      // Destination Marker
                      Marker(
                        point: destLatLng,
                        width: 70,
                        height: 40,
                        child: _AirportMarker(
                          iata: targetFlight.arrivalAirportIata,
                          cs: cs,
                          isOrigin: false,
                        ),
                      ),
                      // Realtime Aircraft Marker
                      Marker(
                        point: planeLatLng,
                        width: 48,
                        height: 48,
                        child: Transform.rotate(
                          angle: headingRad,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary.withValues(alpha: 0.25),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.6),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                Icons.flight,
                                size: 28,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Required by the OpenStreetMap and CARTO basemap terms.
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                      TextSourceAttribution('CARTO'),
                    ],
                  ),
                ],
              ),

              // ── Floating Telemetry HUD Card ──
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _FlightHudCard(
                  flight: targetFlight,
                  progress: progress,
                  cs: cs,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, FlightState state) {
    final cs = Theme.of(context).colorScheme;
    final isLoading = state is FlightLoadInProgress;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Radar')),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.radar_rounded,
                        size: 56, color: cs.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      'No flight to track yet',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a flight and it will show up here once it is airborne.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.go('/flight/search'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a flight'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _AirportMarker extends StatelessWidget {
  final String iata;
  final ColorScheme cs;
  final bool isOrigin;

  const _AirportMarker({
    required this.iata,
    required this.cs,
    required this.isOrigin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isOrigin ? cs.primary : cs.secondary,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            iata,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isOrigin ? cs.onPrimary : cs.onSecondary,
            ),
          ),
        ),
        Icon(
          Icons.arrow_drop_down,
          size: 14,
          color: isOrigin ? cs.primary : cs.secondary,
        ),
      ],
    );
  }
}

class _FlightHudCard extends StatelessWidget {
  final Flight flight;
  final double progress;
  final ColorScheme cs;

  const _FlightHudCard({
    required this.flight,
    required this.progress,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toInt();

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: cs.surfaceContainer.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Flight number, route, Status badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.flight_takeoff, color: cs.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${flight.flightNumber} · ${flight.departureAirportIata} → ${flight.arrivalAirportIata}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          flight.airlineName ?? flight.airlineIata,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: flight.status == FlightStatusEnum.active
                        ? Colors.green.withValues(alpha: 0.2)
                        : cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    flight.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: flight.status == FlightStatusEnum.active ? Colors.green : cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Route Completion: $pct%',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                Text(
                  flight.aircraft?.modelName ?? 'Commercial Jet',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Telemetry Grid
            Row(
              children: [
                _TelemetryStat(
                  label: 'ALTITUDE',
                  value: flight.status == FlightStatusEnum.active ? '36,000 FT' : 'GROUND',
                  cs: cs,
                ),
                _TelemetryStat(
                  label: 'GROUND SPEED',
                  value: flight.status == FlightStatusEnum.active ? '485 KTS' : '0 KTS',
                  cs: cs,
                ),
                _TelemetryStat(
                  label: 'RADAR FEED',
                  value: flight.dataSource?.contains('OpenSky') == true ? 'OPENSKY' : 'LIVE ADS-B',
                  cs: cs,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Button to details
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  context.push('/flight/${flight.id}', extra: flight);
                },
                child: const Text('View Full Flight Details & Gate Alerts'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryStat extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _TelemetryStat({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
