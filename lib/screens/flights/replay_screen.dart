import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../config/map_tiles.dart';
import '../../models/models.dart';
import '../../services/adsb_data_service.dart';
import '../../services/trace_service.dart';
import '../../services/world_traffic_service.dart';

/// Replays a flight along the path the aircraft actually flew.
class ReplayScreen extends StatefulWidget {
  final Flight flight;
  const ReplayScreen({super.key, required this.flight});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  final _map = MapController();
  List<TracePoint> _points = const [];
  bool _loading = true;
  String? _problem;

  double _position = 0; // 0..1 through the recorded path
  bool _playing = false;
  int _speed = 120; // x real time
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final f = widget.flight;
    var points = await TraceService.instance.savedForFlight(f.id);

    if (points.isEmpty) {
      final hex = await _resolveHex(f);
      if (hex != null) {
        points = TraceService.lastLeg(await TraceService.instance.trace(hex));
        // Only keep a leg that plausibly belongs to this flight's day.
        points = points.where((p) => p.time.difference(f.bestDepartureTime).abs() < const Duration(hours: 18)).toList();
        if (points.length > 10) await TraceService.instance.saveForFlight(f.id, points);
      }
    }

    if (!mounted) return;
    setState(() {
      _points = points;
      _loading = false;
      if (points.length < 2) {
        _problem = 'No recorded path for this flight. Paths are kept for about a day after landing — '
            "adding the aircraft's tail number helps find it.";
      }
    });
    if (points.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([for (final p in points) LatLng(p.lat, p.lon)]),
          padding: const EdgeInsets.all(40),
        ));
      });
    }
  }

  Future<String?> _resolveHex(Flight f) async {
    final hex = f.aircraft?.icaoCode;
    if (hex != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return hex.toLowerCase();
    final reg = f.aircraftRegistration;
    if (reg != null && reg.isNotEmpty) {
      final a = await WorldTrafficService.instance.byRegistration(reg);
      if (a != null) return a.hex;
    }
    // Last resort: the aircraft currently using this flight's callsign.
    final live = await AdsbDataService.instance.lookupLivePosition(f.flightNumber);
    return live?.modeSHex.toLowerCase();
  }

  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }
    if (_position >= 1) _position = 0;
    final total = _points.last.time.difference(_points.first.time).inMilliseconds;
    if (total <= 0) return;
    setState(() => _playing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      setState(() {
        _position += 50 * _speed / total;
        if (_position >= 1) {
          _position = 1;
          _playing = false;
          _timer?.cancel();
        }
      });
    });
  }

  TracePoint _pointAt(double t) {
    final start = _points.first.time.millisecondsSinceEpoch;
    final end = _points.last.time.millisecondsSinceEpoch;
    final target = start + ((end - start) * t).round();
    var i = 0;
    while (i < _points.length - 2 && _points[i + 1].time.millisecondsSinceEpoch < target) {
      i++;
    }
    final a = _points[i], b = _points[i + 1];
    final span = b.time.millisecondsSinceEpoch - a.time.millisecondsSinceEpoch;
    final f = span <= 0 ? 0.0 : ((target - a.time.millisecondsSinceEpoch) / span).clamp(0.0, 1.0);
    double lerp(double x, double y) => x + (y - x) * f;
    return TracePoint(
      time: DateTime.fromMillisecondsSinceEpoch(target),
      lat: lerp(a.lat, b.lat),
      lon: lerp(a.lon, b.lon),
      altitudeFt: a.altitudeFt == null || b.altitudeFt == null ? (a.altitudeFt ?? b.altitudeFt) : lerp(a.altitudeFt!, b.altitudeFt!),
      groundSpeedKt: b.groundSpeedKt,
      trackDeg: b.trackDeg,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final f = widget.flight;

    return Scaffold(
      appBar: AppBar(title: Text('Replay · ${f.flightNumber}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _problem != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_problem!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                )
              : _buildReplay(cs, isDark),
    );
  }

  Widget _buildReplay(ColorScheme cs, bool isDark) {
    final now = _pointAt(_position);
    final path = [for (final p in _points) LatLng(p.lat, p.lon)];
    final flown = path.sublist(0, (path.length * _position).round().clamp(1, path.length));

    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(initialCenter: path.first, initialZoom: 5),
            children: [
              MapTiles.layer(isDark: isDark),
              PolylineLayer(polylines: [
                Polyline(points: path, color: cs.outlineVariant, strokeWidth: 2),
                Polyline(points: [...flown, LatLng(now.lat, now.lon)], color: cs.primary, strokeWidth: 3),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: LatLng(now.lat, now.lon),
                  width: 36,
                  height: 36,
                  child: Transform.rotate(
                    angle: (now.trackDeg ?? 0) * 3.14159265 / 180,
                    child: Icon(Icons.flight, color: cs.primary, size: 30),
                  ),
                ),
              ]),
              const RichAttributionWidget(attributions: [
                TextSourceAttribution('Flight path: adsb.lol (ODbL)'),
                TextSourceAttribution('OpenStreetMap contributors'),
              ]),
            ],
          ),
        ),
        SizedBox(
          height: 60,
          child: CustomPaint(
            size: Size.infinite,
            painter: _AltitudeProfile(_points, _position, cs.primary, cs.outlineVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat.Hm().format(now.time), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                    [
                      now.altitudeFt == null ? 'Ground' : '${NumberFormat.decimalPattern().format(now.altitudeFt!.round())} ft',
                      if (now.groundSpeedKt != null) '${now.groundSpeedKt!.round()} kt',
                    ].join(' · '),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _position,
                onChanged: (v) => setState(() => _position = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    iconSize: 30,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 16),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 60, label: Text('60×')),
                      ButtonSegment(value: 120, label: Text('120×')),
                      ButtonSegment(value: 600, label: Text('600×')),
                    ],
                    selected: {_speed},
                    onSelectionChanged: (v) => setState(() => _speed = v.first),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AltitudeProfile extends CustomPainter {
  final List<TracePoint> points;
  final double position;
  final Color color;
  final Color muted;
  _AltitudeProfile(this.points, this.position, this.color, this.muted);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final maxAlt = points.map((p) => p.altitudeFt ?? 0).reduce((a, b) => a > b ? a : b);
    if (maxAlt <= 0) return;
    final start = points.first.time.millisecondsSinceEpoch;
    final span = (points.last.time.millisecondsSinceEpoch - start).toDouble();
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = 12 + (size.width - 24) * (points[i].time.millisecondsSinceEpoch - start) / span;
      final y = size.height - 6 - (size.height - 12) * (points[i].altitudeFt ?? 0) / maxAlt;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = muted);
    final x = 12 + (size.width - 24) * position;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
      ..color = color
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_AltitudeProfile old) => old.position != position || old.points != points;
}
