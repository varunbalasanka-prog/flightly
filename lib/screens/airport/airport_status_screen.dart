import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../services/airport_directory.dart';
import '../../services/cctv_service.dart';
import '../../services/radio_service.dart';
import '../../services/weather_service.dart';
import '../../services/world_traffic_service.dart';
import '../widgets/live_camera_view.dart';
import '../widgets/radio_bar.dart';

/// Live picture of one airport from public data.
///
/// This screen used to show invented numbers: a fixed 22°C, "42 active
/// flights", a delay index from a static table, and three lounges generated
/// for any airport code (one of them a real Amex brand at a made-up gate).
/// Everything here now comes from an observation or a live feed, with its
/// source named.
class AirportStatusScreen extends StatefulWidget {
  final String iataCode;
  const AirportStatusScreen({super.key, required this.iataCode});

  @override
  State<AirportStatusScreen> createState() => _AirportStatusScreenState();
}

class _AirportStatusScreenState extends State<AirportStatusScreen> {
  AirportInfoRecord? _airport;
  bool _resolved = false;
  Metar? _metar;
  LocalWeather? _weather;
  List<TrafficAircraft> _arriving = const [];
  List<TrafficAircraft> _departing = const [];
  int _onGround = 0;
  DateTime? _trafficAt;
  List<CameraMatch> _cameras = const [];
  List<RadioStation> _radio = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadTraffic());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final airport = await AirportDirectory.instance.lookup(widget.iataCode);
    if (!mounted) return;
    setState(() {
      _airport = airport;
      _resolved = true;
    });
    if (airport == null) return;

    await Future.wait([
      WeatherService.instance.metar(airport.icao).then((v) => _metar = v),
      WeatherService.instance.local(airport.lat, airport.lon).then((v) => _weather = v),
      CctvService.instance.nearest(airport.lat, airport.lon, radiusKm: 40, limit: 4).then((v) => _cameras = v),
      RadioService.instance.near(airport.lat, airport.lon, radiusKm: 60, limit: 8).then((v) => _radio = v),
      _loadTraffic(),
    ]);
    if (mounted) setState(() {});
  }

  /// Traffic within 30 nm, split by what each aircraft is actually doing:
  /// low and descending toward the field, or low and climbing away from it.
  Future<void> _loadTraffic() async {
    final a = _airport;
    if (a == null) return;
    final snapshot = await WorldTrafficService.instance.regional(a.lat, a.lon, radiusNm: 30);
    if (snapshot == null || !mounted) return;

    final arriving = <TrafficAircraft>[];
    final departing = <TrafficAircraft>[];
    var ground = 0;
    for (final ac in snapshot.aircraft) {
      if (ac.onGround) {
        ground++;
        continue;
      }
      final alt = ac.altitudeFt ?? 99999;
      final vs = ac.verticalRateFpm ?? 0;
      if (alt < 12000 && vs < -300) arriving.add(ac);
      if (alt < 12000 && vs > 300) departing.add(ac);
    }
    int byAltitude(TrafficAircraft x, TrafficAircraft y) => (x.altitudeFt ?? 0).compareTo(y.altitudeFt ?? 0);
    arriving.sort(byAltitude);
    departing.sort(byAltitude);
    setState(() {
      _arriving = arriving;
      _departing = departing;
      _onGround = ground;
      _trafficAt = snapshot.fetchedAt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = _airport;

    return Scaffold(
      appBar: AppBar(title: Text(a?.name ?? widget.iataCode)),
      bottomNavigationBar: const Padding(padding: EdgeInsets.all(8), child: RadioBar()),
      body: !_resolved
          ? const Center(child: CircularProgressIndicator())
          : a == null
              ? Center(child: Text('No airport with code ${widget.iataCode}.', style: TextStyle(color: cs.onSurfaceVariant)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          '${a.iata} · ${a.icao} · ${a.displayCity}, ${a.countryCode}',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                      _card(
                        'Conditions',
                        Icons.cloud_outlined,
                        _metar == null && _weather == null
                            ? const Text('Weather unavailable right now.')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_weather != null)
                                    Text(
                                      '${_weather!.temperatureC.round()}° · ${_weather!.description}',
                                      style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700),
                                    ),
                                  if (_metar != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if (_metar!.flightCategory != null) _metar!.flightCategory!,
                                        if (_metar!.windKt != null)
                                          'wind ${_metar!.windDirDeg ?? 'VRB'}° ${_metar!.windKt}kt'
                                              '${_metar!.gustKt != null ? ' gusting ${_metar!.gustKt}' : ''}',
                                        if (_metar!.visibilitySm != null) 'visibility ${_metar!.visibilitySm} sm',
                                        if (_metar!.ceilingFt != null) 'ceiling ${_metar!.ceilingFt} ft',
                                      ].join(' · '),
                                    ),
                                    for (final c in _metar!.operationalConcerns)
                                      Text(c, style: TextStyle(color: cs.error, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    SelectableText(_metar!.raw, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                                    Text(
                                      'METAR ${_metar!.observed != null ? timeago.format(_metar!.observed!) : ''}',
                                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      _card(
                        'Live traffic within 30 nm',
                        Icons.flight,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_arriving.length} descending toward the area · ${_departing.length} climbing out · '
                              '$_onGround on the ground',
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (_trafficAt != null)
                              Text('adsb.lol · ${DateFormat.Hms().format(_trafficAt!)}',
                                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            _trafficList('Arriving', _arriving, Icons.flight_land, cs),
                            _trafficList('Departing', _departing, Icons.flight_takeoff, cs),
                            Text(
                              "Based on altitude and climb/descent — it's what's flying now, not a timetable.",
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      _card(
                        'Cameras nearby',
                        Icons.videocam_outlined,
                        _cameras.isEmpty
                            ? Text('No public cameras are published near ${a.displayCity}.',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
                            : SizedBox(
                                height: 200,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _cameras.length,
                                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                                  itemBuilder: (context, i) => SizedBox(
                                    width: 260,
                                    child: LiveCameraView(camera: _cameras[i].camera, distanceKm: _cameras[i].distanceKm),
                                  ),
                                ),
                              ),
                      ),
                      _card(
                        'Local radio',
                        Icons.radio,
                        _radio.isEmpty
                            ? Text('No stations listed nearby.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
                            : Column(
                                children: [
                                  for (final r in _radio)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.play_circle_outline),
                                      title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text(r.tags.take(3).join(', '), maxLines: 1),
                                      onTap: () => RadioPlayer.instance.play(r),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _trafficList(String label, List<TrafficAircraft> list, IconData icon, ColorScheme cs) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: cs.onSurfaceVariant)),
          for (final ac in list.take(6))
            Row(
              children: [
                Icon(icon, size: 14, color: cs.secondary),
                const SizedBox(width: 6),
                SizedBox(width: 90, child: Text(ac.label, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13))),
                Expanded(
                  child: Text(
                    [
                      ac.typeCode,
                      if (ac.altitudeFt != null) '${NumberFormat.decimalPattern().format(ac.altitudeFt!.round())} ft',
                    ].whereType<String>().join(' · '),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _card(String title, IconData icon, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: cs.secondary),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
