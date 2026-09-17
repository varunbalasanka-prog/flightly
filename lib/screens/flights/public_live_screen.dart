import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../config/map_tiles.dart';
import '../../services/adsb_data_service.dart';
import '../../services/trace_service.dart';

/// A shareable, sign-in-free live view of a flight by callsign.
///
/// Shows only public ADS-B data — route, position, altitude, speed and the
/// path flown — never anything from the sharer's account.
class PublicLiveScreen extends StatefulWidget {
  final String callsign;
  const PublicLiveScreen({super.key, required this.callsign});

  @override
  State<PublicLiveScreen> createState() => _PublicLiveScreenState();
}

class _PublicLiveScreenState extends State<PublicLiveScreen> {
  final _map = MapController();
  FlightRoute? _route;
  LivePosition? _live;
  List<LatLng> _path = const [];
  bool _loaded = false;
  bool _centred = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final route = _route ?? await AdsbDataService.instance.lookupRoute(widget.callsign);
    final live = await AdsbDataService.instance.lookupLivePosition(widget.callsign, icaoCallsign: route?.callsignIcao);
    var path = _path;
    if (live != null && (path.isEmpty || !_loaded)) {
      final trace = TraceService.lastLeg(await TraceService.instance.trace(live.modeSHex));
      path = [for (final p in trace) LatLng(p.lat, p.lon)];
    }
    if (!mounted) return;
    setState(() {
      _route = route;
      _live = live;
      _path = path;
      _loaded = true;
    });
    if (live != null && !_centred) {
      _centred = true;
      _map.move(LatLng(live.latitude, live.longitude), 6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final live = _live;
    final route = _route;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.callsign} · live'),
        actions: [TextButton(onPressed: () => context.go('/login'), child: const Text('Open SkyPulse'))],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(initialCenter: LatLng(25, 10), initialZoom: 2),
            children: [
              MapTiles.layer(isDark: isDark),
              if (route != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: [
                      LatLng(route.origin.latitude, route.origin.longitude),
                      LatLng(route.destination.latitude, route.destination.longitude),
                    ],
                    color: cs.outlineVariant,
                    strokeWidth: 1.5,
                  ),
                  if (_path.length > 1) Polyline(points: _path, color: cs.primary, strokeWidth: 3),
                ]),
              if (live != null)
                MarkerLayer(markers: [
                  Marker(
                    point: LatLng(live.latitude, live.longitude),
                    width: 40,
                    height: 40,
                    child: Transform.rotate(
                      angle: (live.headingDegrees ?? 0) * 3.14159265 / 180,
                      child: Icon(Icons.flight, color: cs.primary, size: 34),
                    ),
                  ),
                ]),
              const RichAttributionWidget(attributions: [
                TextSourceAttribution('adsb.lol (ODbL) · adsbdb'),
                TextSourceAttribution('OpenStreetMap contributors'),
              ]),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: !_loaded
                    ? const LinearProgressIndicator()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            route != null
                                ? '${route.origin.iataCode} → ${route.destination.iataCode} · ${route.airlineName}'
                                : widget.callsign,
                            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            live == null
                                ? 'Not airborne right now, or outside ADS-B coverage.'
                                : live.onGround
                                    ? 'On the ground'
                                    : [
                                        if (live.altitudeFeet != null)
                                          '${NumberFormat.decimalPattern().format(live.altitudeFeet!.round())} ft',
                                        if (live.groundSpeedKnots != null) '${live.groundSpeedKnots!.round()} kt',
                                        'updated ${DateFormat.Hms().format(live.observedAt)}',
                                      ].join(' · '),
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
