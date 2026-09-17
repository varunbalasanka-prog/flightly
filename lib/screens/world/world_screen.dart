import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../blocs/flight/flight_bloc.dart';
import '../../config/map_tiles.dart';
import '../../config/sensor_styles.dart';
import '../../services/adsb_data_service.dart';
import '../../services/airport_directory.dart';
import '../../services/cctv_service.dart';
import '../../services/military_installation_service.dart';
import '../../services/place_intel_service.dart';
import '../../services/radio_service.dart';
import '../../services/trace_service.dart';
import '../../services/world_traffic_service.dart';
import '../../utils/aircraft_classifier.dart';
import '../../utils/motion_model.dart';
import '../../utils/route_plausibility.dart';
import '../widgets/live_camera_view.dart';
import '../widgets/radio_bar.dart';
import 'world_glyph_layer.dart';

enum WorldLayer {
  flights('Flights', Icons.flight),
  military('Military flights', Icons.shield_outlined),
  installations('Military installations', Icons.fort_outlined),
  radio('Radio stations', Icons.radio),
  cameras('Public cameras', Icons.videocam_outlined),
  earthquakes('Earthquakes', Icons.waves),
  satellites('Satellites', Icons.satellite_alt);

  final String label;
  final IconData icon;
  const WorldLayer(this.label, this.icon);
}

/// The whole-planet view: live aircraft, military traffic and installations,
/// radio, public cameras, earthquakes and satellites on one map.
class WorldScreen extends StatefulWidget {
  const WorldScreen({super.key});

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen> {
  static const _civilColor = Color(0xFF7DD3FC);
  static const _groundColor = Color(0xFF94A3B8);
  static const _militaryColor = Color(0xFFF59E0B);
  static const _mineColor = Color(0xFF34D399);
  static const _baseColor = Color(0xFFEF4444);
  static const _radioColor = Color(0xFFC084FC);
  static const _cameraColor = Color(0xFF2DD4BF);
  static const _quakeColor = Color(0xFFF87171);
  static const _satColor = Color(0xFFE5E7EB);

  /// Below this zoom the map shows the worldwide snapshot; above it, live
  /// regional traffic around the map centre.
  static const _regionalZoom = 5.5;
  static const _installationZoom = 6.0;

  final _map = MapController();
  final Set<WorldLayer> _layers = {WorldLayer.flights, WorldLayer.military};
  SensorStyle _sensor = SensorStyle.normal;
  bool _satelliteBasemap = false;

  TrafficSnapshot? _traffic;
  TrafficSnapshot? _military;
  List<MilitaryInstallation> _installations = const [];
  List<RadioStation> _radio = const [];
  List<PublicCamera> _cameras = const [];
  List<Earthquake> _quakes = const [];
  List<SatellitePosition> _satellites = const [];

  final _previousFixes = <String, MotionFix>{};
  final _latestFixes = <String, MotionFix>{};
  Set<String> _myCallsigns = const {};

  Object? _selected;
  String? _followHex;
  List<LatLng> _selectedTrail = const [];
  String? _selectedRouteText;
  String? _selectedPhotoUrl;

  bool _loadingTraffic = false;
  Timer? _trafficTimer;
  Timer? _motionTimer;
  Timer? _slowTimer;
  Timer? _moveDebounce;

  @override
  void initState() {
    super.initState();
    AirportDirectory.instance.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTraffic();
      _refreshSlowLayers();
    });
    _trafficTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refreshTraffic());
    _slowTimer = Timer.periodic(const Duration(seconds: 45), (_) => _refreshSlowLayers());
    // Repaint once a second so regional aircraft glide between fixes.
    _motionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _traffic?.source == TrafficSource.adsbRegional) setState(() {});
    });
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    _slowTimer?.cancel();
    _motionTimer?.cancel();
    _moveDebounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────

  MapCamera? get _camera {
    try {
      return _map.camera;
    } catch (_) {
      return null; // not attached yet
    }
  }

  Future<void> _refreshTraffic() async {
    final camera = _camera;
    if (camera == null || !mounted || _loadingTraffic) return;
    _loadingTraffic = true;
    try {
      if (_layers.contains(WorldLayer.flights)) {
        TrafficSnapshot? snapshot;
        if (camera.zoom >= _regionalZoom) {
          final c = camera.center;
          final ne = camera.visibleBounds.northEast;
          final radiusNm = (haversineKm(c.latitude, c.longitude, ne.latitude, ne.longitude) / 1.852).clamp(10, 250);
          snapshot = await WorldTrafficService.instance.regional(c.latitude, c.longitude, radiusNm: radiusNm.round());
        } else {
          snapshot = await WorldTrafficService.instance.global();
        }
        if (snapshot != null) _ingest(snapshot);
        if (mounted) setState(() => _traffic = snapshot ?? _traffic);
      }
      if (_layers.contains(WorldLayer.military)) {
        final mil = await WorldTrafficService.instance.military();
        if (mil != null) _ingest(mil);
        if (mounted) setState(() => _military = mil ?? _military);
      }
      _followSelected();
    } finally {
      _loadingTraffic = false;
    }
  }

  void _ingest(TrafficSnapshot snapshot) {
    for (final a in snapshot.aircraft) {
      final fix = MotionFix(
        time: snapshot.fetchedAt,
        lat: a.lat,
        lon: a.lon,
        trackDeg: a.trackDeg,
        groundSpeedKt: a.groundSpeedKt,
      );
      final latest = _latestFixes[a.hex];
      if (latest != null && latest.time != fix.time) _previousFixes[a.hex] = latest;
      _latestFixes[a.hex] = fix;
    }
    if (_latestFixes.length > 40000) {
      _latestFixes.clear();
      _previousFixes.clear();
    }
  }

  Future<void> _refreshSlowLayers() async {
    final camera = _camera;
    if (camera == null || !mounted) return;

    final jobs = <Future<void>>[];
    if (_layers.contains(WorldLayer.installations) && camera.zoom >= _installationZoom) {
      final b = camera.visibleBounds;
      jobs.add(MilitaryInstallationService.instance
          .inBounds(south: b.south, west: b.west, north: b.north, east: b.east)
          .then((v) => _installations = v));
    }
    if (_layers.contains(WorldLayer.radio) && _radio.isEmpty) {
      jobs.add(RadioService.instance.global().then((v) => _radio = v));
    }
    if (_layers.contains(WorldLayer.cameras) && _cameras.isEmpty) {
      jobs.add(CctvService.instance.catalog().then((v) => _cameras = v));
    }
    if (_layers.contains(WorldLayer.earthquakes)) {
      jobs.add(DisruptionService.instance.earthquakes().then((v) => _quakes = v));
    }
    if (_layers.contains(WorldLayer.satellites)) {
      jobs.add(OrbitalService.instance.positions(group: 'visual').then((v) => _satellites = v.satellites));
    }
    await Future.wait(jobs);
    if (mounted) setState(() {});
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd || event is MapEventDoubleTapZoomEnd || event is MapEventScrollWheelZoom) {
      _moveDebounce?.cancel();
      _moveDebounce = Timer(const Duration(milliseconds: 600), () {
        _refreshTraffic();
        _refreshSlowLayers();
      });
    }
  }

  Future<void> _resolveMyFlights(FlightState state) async {
    if (state is! FlightLoadSuccess) return;
    final callsigns = <String>{};
    for (final f in state.flights.where((f) => !f.status.isTerminal)) {
      callsigns.add(f.flightNumber.toUpperCase().replaceAll(' ', ''));
      final route = await AdsbDataService.instance.lookupRoute(f.flightNumber);
      if (route?.callsignIcao.isNotEmpty == true) callsigns.add(route!.callsignIcao);
    }
    if (mounted) setState(() => _myCallsigns = callsigns);
  }

  // ── Glyphs ──────────────────────────────────────────────────────────────

  List<WorldGlyph> _buildGlyphs() {
    final glyphs = <WorldGlyph>[];
    final regional = _traffic?.source == TrafficSource.adsbRegional;

    if (_layers.contains(WorldLayer.earthquakes)) {
      for (final q in _quakes) {
        glyphs.add(WorldGlyph(
          lat: q.lat, lon: q.lon, shape: GlyphShape.ring, color: _quakeColor,
          size: 3 + q.magnitude * 1.8, payload: q,
        ));
      }
    }
    if (_layers.contains(WorldLayer.cameras) && (_camera?.zoom ?? 0) >= 4) {
      for (final c in _cameras) {
        glyphs.add(WorldGlyph(lat: c.lat, lon: c.lon, shape: GlyphShape.square, color: _cameraColor, size: 3, payload: c));
      }
    }
    if (_layers.contains(WorldLayer.radio)) {
      for (final r in _radio) {
        if (r.lat == null || r.lon == null) continue;
        glyphs.add(WorldGlyph(lat: r.lat!, lon: r.lon!, shape: GlyphShape.dot, color: _radioColor, payload: r));
      }
    }
    if (_layers.contains(WorldLayer.installations)) {
      for (final b in _installations) {
        glyphs.add(WorldGlyph(lat: b.lat, lon: b.lon, shape: GlyphShape.diamond, color: _baseColor, size: 6, payload: b));
      }
    }
    if (_layers.contains(WorldLayer.satellites)) {
      for (final s in _satellites) {
        glyphs.add(WorldGlyph(
          lat: s.lat, lon: s.lon, shape: GlyphShape.dot,
          color: s.noradId == 25544 ? Colors.white : _satColor.withValues(alpha: 0.7),
          payload: s,
        ));
      }
    }

    final seen = <String>{};
    void addAircraft(TrafficAircraft a) {
      if (!seen.add(a.hex)) return;
      final mine = _myCallsigns.contains(a.callsign.toUpperCase());
      var lat = a.lat, lon = a.lon, track = a.trackDeg ?? 0;
      if (regional && !a.onGround) {
        final latest = _latestFixes[a.hex];
        if (latest != null) {
          final p = MotionModel.predict(latest, previous: _previousFixes[a.hex]);
          lat = p.lat;
          lon = p.lon;
          track = p.trackDeg;
        }
      }
      final cls = AircraftClassifier.classify(typeCode: a.typeCode, category: a.category);
      glyphs.add(WorldGlyph(
        lat: lat,
        lon: lon,
        shape: cls == AircraftClass.helicopter ? GlyphShape.helicopter : GlyphShape.plane,
        color: mine
            ? _mineColor
            : a.military
                ? _militaryColor
                : a.onGround
                    ? _groundColor
                    : _civilColor,
        size: mine ? 11 : (cls == AircraftClass.widebody || cls == AircraftClass.quadjet ? 8 : 6.5),
        rotationDeg: track,
        payload: a,
      ));
    }

    // Military first so it wins de-duplication over the civil feed.
    if (_layers.contains(WorldLayer.military)) _military?.aircraft.forEach(addAircraft);
    if (_layers.contains(WorldLayer.flights)) _traffic?.aircraft.forEach(addAircraft);
    return glyphs;
  }

  // ── Selection ───────────────────────────────────────────────────────────

  void _onTap(TapPosition tap, LatLng point, List<WorldGlyph> glyphs) {
    final camera = _camera;
    if (camera == null) return;
    final hit = WorldGlyphLayer.hitTest(camera, tap.relative ?? Offset.zero, glyphs);
    setState(() {
      _selected = hit?.payload;
      _selectedTrail = const [];
      _selectedRouteText = null;
      _selectedPhotoUrl = null;
      if (hit == null) _followHex = null;
    });
    final payload = hit?.payload;
    if (payload is TrafficAircraft) _enrichAircraft(payload);
  }

  Future<void> _enrichAircraft(TrafficAircraft a) async {
    final record = await AdsbDataService.instance.lookupAircraft(a.hex);
    if (!mounted || _selected != a) return;
    setState(() => _selectedPhotoUrl = record?.photoThumbnailUrl);

    if (a.callsign.isEmpty) return;
    final route = await AdsbDataService.instance.lookupRoute(a.callsign);
    if (!mounted || _selected != a) return;
    if (route == null) {
      setState(() => _selectedRouteText = 'Route not in the public database');
      return;
    }
    final ok = RoutePlausibility.plausible(
      lat: a.lat, lon: a.lon, altitudeFt: a.altitudeFt, verticalRateFpm: a.verticalRateFpm,
      originLat: route.origin.latitude, originLon: route.origin.longitude,
      destLat: route.destination.latitude, destLon: route.destination.longitude,
    );
    setState(() => _selectedRouteText = ok
        ? '${route.origin.iataCode} → ${route.destination.iataCode} · ${route.airlineName}'
        : 'Listed route (${route.origin.iataCode} → ${route.destination.iataCode}) does not match where it is flying');
  }

  Future<void> _showFlownPath(TrafficAircraft a) async {
    final points = TraceService.lastLeg(await TraceService.instance.trace(a.hex));
    if (!mounted) return;
    setState(() => _selectedTrail = [for (final p in points) LatLng(p.lat, p.lon)]);
    if (points.isEmpty) _snack('No recorded path for this aircraft yet.');
  }

  void _followSelected() {
    final hex = _followHex;
    if (hex == null) return;
    final fix = _latestFixes[hex];
    final camera = _camera;
    if (fix != null && camera != null) _map.move(LatLng(fix.lat, fix.lon), camera.zoom);
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // ── UI ──────────────────────────────────────────────────────────────────

  String _statusText() {
    final parts = <String>[];
    final t = _traffic;
    if (_layers.contains(WorldLayer.flights) && t != null) {
      if (t.limitation != null && t.aircraft.isEmpty) {
        return t.limitation!;
      }
      parts.add('${_fmt(t.aircraft.length)} aircraft');
      parts.add(t.source == TrafficSource.adsbRegional
          ? 'live · adsb.lol'
          : 'worldwide · OpenSky · ${timeago.format(t.fetchedAt)}');
    }
    if (_layers.contains(WorldLayer.military) && _military != null) {
      parts.add('${_military!.aircraft.length} military');
    }
    if (_layers.contains(WorldLayer.installations) && (_camera?.zoom ?? 0) < _installationZoom) {
      parts.add('zoom in for installations');
    }
    return parts.isEmpty ? 'Loading…' : parts.join(' · ');
  }

  static String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  void _openLayers() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void toggle(WorldLayer l, bool on) {
            setState(() => on ? _layers.add(l) : _layers.remove(l));
            setSheet(() {});
            _refreshTraffic();
            _refreshSlowLayers();
          }

          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('Layers', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
              for (final l in WorldLayer.values)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(l.icon),
                  title: Text(l.label),
                  subtitle: Text(_layerNote(l), style: const TextStyle(fontSize: 11)),
                  value: _layers.contains(l),
                  onChanged: (v) => toggle(l, v),
                ),
              const Divider(),
              Text('Map', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.public),
                title: const Text('Satellite imagery'),
                value: _satelliteBasemap,
                onChanged: (v) {
                  setState(() => _satelliteBasemap = v);
                  setSheet(() {});
                },
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in SensorStyle.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _sensor == s,
                      onSelected: (_) {
                        setState(() => _sensor = s);
                        setSheet(() {});
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _layerNote(WorldLayer l) => switch (l) {
        WorldLayer.flights => 'OpenSky worldwide; adsb.lol live when zoomed in',
        WorldLayer.military => 'Aircraft broadcasting military ADS-B (adsb.lol)',
        WorldLayer.installations => 'OpenStreetMap community mapping — incomplete',
        WorldLayer.radio => 'Geotagged internet stations (Radio Browser)',
        WorldLayer.cameras => 'Public road & weather cameras in ${CctvService.coverage.length} regions',
        WorldLayer.earthquakes => 'USGS, last 24 hours',
        WorldLayer.satellites => 'Brightest satellites and the ISS (CelesTrak)',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glyphs = _buildGlyphs();

    Widget basemap = _satelliteBasemap ? MapTiles.satelliteLayer() : MapTiles.layer(isDark: isDark);
    final filter = _sensor.filter;
    if (filter != null) basemap = ColorFiltered(colorFilter: filter, child: basemap);

    return BlocListener<FlightBloc, FlightState>(
      listener: (context, state) => _resolveMyFlights(state),
      child: Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: const LatLng(25, 10),
                initialZoom: 2.2,
                minZoom: 1.5,
                maxZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (tap, point) => _onTap(tap, point, glyphs),
                onMapEvent: _onMapEvent,
                onMapReady: () {
                  _refreshTraffic();
                  _resolveMyFlights(context.read<FlightBloc>().state);
                },
              ),
              children: [
                basemap,
                if (_selectedTrail.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(points: _selectedTrail, color: _mineColor, strokeWidth: 2.5),
                  ]),
                WorldGlyphLayer(glyphs: glyphs),
                _satelliteBasemap ? MapTiles.satelliteAttribution() : MapTiles.attribution(),
              ],
            ),

            // Top bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('World', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                            Text(
                              _statusText(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RoundButton(icon: Icons.layers_outlined, tooltip: 'Layers & map style', onTap: _openLayers),
                    const SizedBox(width: 6),
                    _RoundButton(
                      icon: Icons.chat_bubble_outline,
                      tooltip: 'Ask the flight assistant',
                      onTap: () => context.push('/assistant'),
                    ),
                    const SizedBox(width: 6),
                    _RoundButton(
                      icon: Icons.public,
                      tooltip: 'Whole world',
                      onTap: () {
                        setState(() => _followHex = null);
                        _map.move(const LatLng(25, 10), 2.2);
                        _refreshTraffic();
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Bottom: selection card + radio bar
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selected != null) _selectionCard(cs),
                  const SizedBox(height: 8),
                  const RadioBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionCard(ColorScheme cs) {
    final s = _selected;
    Widget body;
    if (s is TrafficAircraft) {
      body = _aircraftCard(s, cs);
    } else if (s is MilitaryInstallation) {
      body = _infoCard(
        icon: Icons.fort_outlined,
        color: _baseColor,
        title: s.name,
        lines: [
          s.kindLabel,
          if (s.operator != null) 'Operator: ${s.operator}',
          'Community-mapped on OpenStreetMap. Mapping of military sites is incomplete.',
        ],
      );
    } else if (s is RadioStation) {
      body = _infoCard(
        icon: Icons.radio,
        color: _radioColor,
        title: s.name,
        lines: [
          [s.state, s.countryCode].where((v) => v.isNotEmpty).join(', '),
          if (s.tags.isNotEmpty) s.tags.take(4).join(' · '),
        ],
        actions: [
          FilledButton.icon(
            onPressed: () => RadioPlayer.instance.play(s),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Listen'),
          ),
        ],
      );
    } else if (s is PublicCamera) {
      body = LiveCameraView(camera: s, refreshEvery: const Duration(seconds: 15));
    } else if (s is Earthquake) {
      body = _infoCard(
        icon: Icons.waves,
        color: _quakeColor,
        title: 'Magnitude ${s.magnitude.toStringAsFixed(1)}',
        lines: [s.place, timeago.format(s.time)],
        actions: [
          if (s.url.isNotEmpty)
            TextButton(onPressed: () => launchUrl(Uri.parse(s.url)), child: const Text('USGS details')),
        ],
      );
    } else if (s is SatellitePosition) {
      body = _infoCard(
        icon: Icons.satellite_alt,
        color: _satColor,
        title: s.name,
        lines: ['Altitude ${s.altitudeKm.round()} km', 'NORAD ${s.noradId}'],
      );
    } else {
      return const SizedBox.shrink();
    }

    return Material(
      color: cs.surface.withValues(alpha: 0.95),
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              body,
              Positioned(
                right: -8,
                top: -8,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _selected = null;
                    _followHex = null;
                    _selectedTrail = const [];
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aircraftCard(TrafficAircraft a, ColorScheme cs) {
    final cls = AircraftClassifier.classify(typeCode: a.typeCode, category: a.category);
    String? num(double? v, String unit, {int digits = 0}) =>
        v == null ? null : '${v.toStringAsFixed(digits)} $unit';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (_selectedPhotoUrl != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _selectedPhotoUrl!,
                    width: 72,
                    height: 48,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          a.label,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (a.military) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _militaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('MILITARY', style: TextStyle(fontSize: 10, color: _militaryColor, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    [a.typeDescription ?? a.typeCode ?? cls.label, a.registration].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_selectedRouteText != null) ...[
          const SizedBox(height: 6),
          Text(_selectedRouteText!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final (label, value) in [
              ('ALT', a.onGround ? 'Ground' : num(a.altitudeFt, 'ft')),
              ('SPD', num(a.groundSpeedKt, 'kt')),
              ('HDG', a.trackDeg == null ? null : '${a.trackDeg!.round()}°'),
              ('V/S', num(a.verticalRateFpm, 'fpm')),
            ])
              if (value != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant, letterSpacing: 1)),
                    Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _followHex = _followHex == a.hex ? null : a.hex;
                _followSelected();
              }),
              icon: Icon(_followHex == a.hex ? Icons.gps_fixed : Icons.gps_not_fixed, size: 16),
              label: Text(_followHex == a.hex ? 'Following' : 'Follow'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showFlownPath(a),
              icon: const Icon(Icons.timeline, size: 16),
              label: const Text('Flown path'),
            ),
            FilledButton.icon(
              onPressed: () => context.push('/cockpit', extra: {'hex': a.hex, 'callsign': a.callsign}),
              icon: const Icon(Icons.flight_takeoff, size: 16),
              label: const Text('Cockpit'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required List<String> lines,
    List<Widget> actions = const [],
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final l in lines.where((l) => l.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: actions),
        ],
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onTap),
    );
  }
}
