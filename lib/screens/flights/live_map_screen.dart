import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../blocs/flight/flight_bloc.dart';
import '../../config/map_tiles.dart';
import '../../models/models.dart';
import '../../services/adsb_data_service.dart';
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

  /// The aircraft's actual broadcast position, when it is airborne and within
  /// ADS-B coverage. Null means we genuinely do not know where it is -- the
  /// marker then falls back to an estimate that is labelled as such.
  LivePosition? _livePosition;

  /// Real airport coordinates for this flight, from adsbdb. The local table
  /// only holds 19 airports, and routes now resolve worldwide.
  FlightRoute? _route;
  Timer? _positionTimer;
  String? _trackedCallsign;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // ADS-B fixes arrive every few seconds; refreshing every 20s is responsive
    // without hammering a free service.
    _positionTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshLivePosition(),
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Fetches the current transponder fix for [callsign], once per callsign
  /// change and then on the refresh timer.
  Future<void> _refreshLivePosition([String? callsign]) async {
    final target = callsign ?? _trackedCallsign;
    if (target == null || target.isEmpty) return;
    _trackedCallsign = target;

    final position = await AdsbDataService.instance.lookupLivePosition(target);
    if (!mounted) return;
    setState(() => _livePosition = position);
  }

  /// Resolves real airport coordinates once per flight. Cached for 24h by the
  /// service, so this is a single request per route.
  Future<void> _resolveRoute(String callsign) async {
    final route = await AdsbDataService.instance.lookupRoute(callsign);
    if (!mounted || route == null) return;
    setState(() => _route = route);
  }

  /// Kicks off a fetch when the screen first learns which flight it is showing.
  void _ensureTracking(String callsign) {
    if (_trackedCallsign == callsign) return;
    _trackedCallsign = callsign;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLivePosition(callsign);
      _resolveRoute(callsign);
    });
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

        // Airport coordinates, in order of trust: the resolved route, then the
        // built-in table. These used to fall back to hard-coded JFK and LHR,
        // so any airport outside the 19-entry table was silently drawn in the
        // wrong place -- and routes now resolve worldwide (6E204 is HYD-COK,
        // neither of which that fallback would have handled correctly).
        _ensureTracking(targetFlight.flightNumber);

        final originLatLng = _resolveAirport(
          targetFlight.departureAirportIata,
          _route?.origin,
        );
        final destLatLng = _resolveAirport(
          targetFlight.arrivalAirportIata,
          _route?.destination,
        );

        if (originLatLng == null || destLatLng == null) {
          return _buildUnmappableState(context, targetFlight);
        }

        // Calculate great-circle arc coordinates
        final rawCoords = AviationDataService.instance.calculateGreatCircleCoordinates(
          originLatLng.latitude,
          originLatLng.longitude,
          destLatLng.latitude,
          destLatLng.longitude,
          points: 40,
        );
        final polylinePoints = rawCoords.map((c) => LatLng(c[0], c[1])).toList();

        // Prefer the aircraft's actual broadcast position. Only when there is
        // no transponder fix do we fall back to interpolating along the route,
        // and the HUD says so rather than presenting the estimate as live.
        final live = _livePosition;
        final hasLiveFix = live != null && !live.onGround;

        final now = DateTime.now();
        final depTime = targetFlight.actualDeparture ?? targetFlight.scheduledDeparture;
        final arrTime = targetFlight.actualArrival ?? targetFlight.scheduledArrival;
        final totalDuration = arrTime.difference(depTime).inSeconds;

        double progress = 0.45;
        if (totalDuration > 0) {
          final elapsed = now.difference(depTime).inSeconds;
          progress = (elapsed / totalDuration).clamp(0.05, 0.95);
          if (targetFlight.status == FlightStatusEnum.scheduled) progress = 0.02;
          if (targetFlight.status == FlightStatusEnum.landed) progress = 1.0;
        }

        final index = (progress * (polylinePoints.length - 1)).floor();
        final nextIndex = min(index + 1, polylinePoints.length - 1);
        final estimatedLatLng = polylinePoints[index];
        final nextLatLng = polylinePoints[nextIndex];

        final planeLatLng = hasLiveFix
            ? LatLng(live.latitude, live.longitude)
            : estimatedLatLng;

        // The aircraft broadcasts its own track; only derive one when it does not.
        final headingRad = hasLiveFix && live.headingDegrees != null
            ? live.headingDegrees! * pi / 180.0
            : atan2(
                nextLatLng.longitude - estimatedLatLng.longitude,
                nextLatLng.latitude - estimatedLatLng.latitude,
              );

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
                  MapTiles.layer(isDark: isDark),
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
                  MapTiles.attribution(),
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
                  live: hasLiveFix ? live : null,
                  cs: cs,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Real coordinates for an airport, or null when we simply do not know.
  LatLng? _resolveAirport(String iata, RouteAirport? fromRoute) {
    if (fromRoute != null && fromRoute.iataCode == iata) {
      return LatLng(fromRoute.latitude, fromRoute.longitude);
    }
    final record = AviationDataService.airports[iata];
    if (record != null) return LatLng(record.lat, record.lng);
    return null;
  }

  Widget _buildUnmappableState(BuildContext context, Flight flight) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('${flight.flightNumber} · Live Radar')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public_off, size: 56, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Route map unavailable',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We don't have coordinates for "
                '${flight.departureAirportIata} or '
                '${flight.arrivalAirportIata} yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
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

String _thousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _FlightHudCard extends StatelessWidget {
  final Flight flight;
  final double progress;

  /// The aircraft's broadcast fix, or null when nothing is being received.
  final LivePosition? live;
  final ColorScheme cs;

  const _FlightHudCard({
    required this.flight,
    required this.progress,
    required this.live,
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
                  live != null
                      ? 'Route Completion: $pct%'
                      : 'Estimated progress: $pct%',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                Text(
                  // Was 'Commercial Jet' whenever the type was unknown.
                  flight.aircraft?.modelName ?? live?.aircraftType ?? '—',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Telemetry Grid
            Row(
              children: [
                // These were fixed strings -- every active flight reported
                // "36,000 FT" and "485 KTS". They now show what the aircraft
                // actually broadcast, or an em dash when nothing is being
                // received.
                _TelemetryStat(
                  label: 'ALTITUDE',
                  value: live?.altitudeFeet != null
                      ? '${_thousands(live!.altitudeFeet!.round())} FT'
                      : '—',
                  cs: cs,
                ),
                _TelemetryStat(
                  label: 'GROUND SPEED',
                  value: live?.groundSpeedKnots != null
                      ? '${live!.groundSpeedKnots!.round()} KTS'
                      : '—',
                  cs: cs,
                ),
                _TelemetryStat(
                  label: 'POSITION',
                  value: live != null ? 'LIVE ADS-B' : 'ESTIMATED',
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
