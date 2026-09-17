import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../blocs/flight/flight_bloc.dart';
import '../../models/models.dart';
import '../../services/airport_directory.dart';
import '../../services/cctv_service.dart';
import '../../services/data_gateway.dart';
import '../../services/place_intel_service.dart';
import '../../services/radio_service.dart';
import '../../services/weather_service.dart';
import '../widgets/live_camera_view.dart';
import 'radio_picker_sheet.dart';

/// Everything about where a flight is going: live weather, a local radio
/// station, public cameras showing current conditions, news and disruptions.
class DestinationPanel extends StatefulWidget {
  final Flight flight;
  const DestinationPanel({super.key, required this.flight});

  @override
  State<DestinationPanel> createState() => _DestinationPanelState();
}

class _DestinationPanelState extends State<DestinationPanel> {
  AirportInfoRecord? _airport;
  bool _resolved = false;

  Future<Metar?>? _metar;
  Future<LocalWeather?>? _weather;
  Future<List<CameraMatch>>? _cameras;
  Future<List<NewsArticle>>? _news;
  Future<List<Earthquake>>? _quakes;
  Future<List<List>>? _fires;
  Future<IssPass?>? _iss;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant DestinationPanel old) {
    super.didUpdateWidget(old);
    if (old.flight.arrivalAirportIata != widget.flight.arrivalAirportIata) _resolve();
  }

  Future<void> _resolve() async {
    final airport = await AirportDirectory.instance.lookup(widget.flight.arrivalAirportIata);
    if (!mounted) return;
    setState(() {
      _airport = airport;
      _resolved = true;
      if (airport == null) return;
      _metar = WeatherService.instance.metar(airport.icao);
      _weather = WeatherService.instance.local(airport.lat, airport.lon);
      _cameras = CctvService.instance.nearest(airport.lat, airport.lon, radiusKm: 60, limit: 6);
      _news = NewsService.instance.about(airport.displayCity);
      _quakes = DisruptionService.instance.near(airport.lat, airport.lon);
      _fires = _loadFires(airport);
      _iss = OrbitalService.instance
          .positions(group: 'stations', passLat: airport.lat, passLon: airport.lon)
          .then((r) => r.issPass);
    });
  }

  Future<List<List>> _loadFires(AirportInfoRecord a) async {
    final data = await DataGateway.instance.proxy('firms', {
      'south': a.lat - 1, 'west': a.lon - 1, 'north': a.lat + 1, 'east': a.lon + 1,
    });
    final fires = data is Map ? data['fires'] as List? : null;
    return fires?.cast<List>() ?? const [];
  }

  Future<void> _chooseRadio() async {
    final airport = _airport;
    if (airport == null) return;
    final chosen = await showRadioPicker(
      context,
      destination: airport,
      currentUuid: widget.flight.destinationRadio?['stationuuid'] as String?,
    );
    if (chosen == null || !mounted) return;
    try {
      await context.read<FlightBloc>().updateFlight(widget.flight.copyWith(destinationRadio: chosen.toJson()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${chosen.name} saved for this trip')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save the station.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final airport = _airport;

    if (!_resolved) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (airport == null) {
      return _Section(
        title: 'Destination',
        child: Text(
          "We don't have details for ${widget.flight.arrivalAirportIata} yet.",
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'AT YOUR DESTINATION · ${airport.displayCity.toUpperCase()}',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: cs.primary),
          ),
        ),
        _weatherSection(airport, cs),
        _radioSection(airport, cs),
        _cameraSection(airport, cs),
        _newsSection(airport, cs),
        _disruptionSection(airport, cs),
        _skySection(airport, cs),
      ],
    );
  }

  // ── Weather ─────────────────────────────────────────────────────────────

  Widget _weatherSection(AirportInfoRecord airport, ColorScheme cs) {
    return _Section(
      title: 'Weather now',
      icon: Icons.cloud_outlined,
      child: FutureBuilder(
        future: Future.wait([_metar!, _weather!]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const _Loading();
          final metar = snapshot.data![0] as Metar?;
          final local = snapshot.data![1] as LocalWeather?;
          if (metar == null && local == null) {
            return Text('Weather is unavailable right now.', style: TextStyle(color: cs.onSurfaceVariant));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (local != null)
                Row(
                  children: [
                    Text(
                      '${local.temperatureC.round()}°',
                      style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(local.description, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                          Text(
                            'Feels ${local.apparentC.round()}° · wind ${local.windKmh.round()} km/h · cloud ${local.cloudCoverPct}%',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (local != null && local.nextHours.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 62,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final h in local.nextHours.take(12))
                        Container(
                          width: 58,
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(DateFormat.j().format(h.time), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                              Text('${h.temperatureC.round()}°', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                              Text('${h.precipitationProbability}%', style: TextStyle(fontSize: 10, color: cs.secondary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Text('Local time · chance of rain', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
              if (metar != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (metar.flightCategory != null)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _categoryColor(metar.flightCategory!).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          metar.flightCategory!,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _categoryColor(metar.flightCategory!)),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        'Airport report ${metar.observed != null ? timeago.format(metar.observed!) : ''}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                for (final c in metar.operationalConcerns)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 14, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text(c, style: TextStyle(fontSize: 12, color: cs.error))),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                SelectableText(metar.raw, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ],
              const SizedBox(height: 4),
              Text('Open-Meteo · aviationweather.gov', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          );
        },
      ),
    );
  }

  static Color _categoryColor(String cat) => switch (cat) {
        'VFR' => Colors.green,
        'MVFR' => Colors.blue,
        'IFR' => Colors.redAccent,
        'LIFR' => Colors.purpleAccent,
        _ => Colors.grey,
      };

  // ── Radio ───────────────────────────────────────────────────────────────

  Widget _radioSection(AirportInfoRecord airport, ColorScheme cs) {
    final saved = widget.flight.destinationRadio;
    final station = saved == null ? null : RadioStation.fromJson(saved);
    final player = RadioPlayer.instance;

    return _Section(
      title: 'Local radio',
      icon: Icons.radio,
      child: station == null
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    'Pick a station in ${airport.displayCity} for local news and music.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ),
                FilledButton.tonal(onPressed: _chooseRadio, child: const Text('Choose')),
              ],
            )
          : ValueListenableBuilder<RadioStation?>(
              valueListenable: player.current,
              builder: (context, playing, _) {
                final isPlaying = playing?.uuid == station.uuid;
                return Row(
                  children: [
                    IconButton.filled(
                      tooltip: isPlaying ? 'Stop' : 'Listen',
                      icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                      onPressed: () => isPlaying ? player.stop() : player.play(station),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(station.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          Text(
                            station.tags.take(3).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(onPressed: _chooseRadio, child: const Text('Change')),
                  ],
                );
              },
            ),
    );
  }

  // ── Cameras ─────────────────────────────────────────────────────────────

  Widget _cameraSection(AirportInfoRecord airport, ColorScheme cs) {
    return _Section(
      title: 'Live cameras',
      icon: Icons.videocam_outlined,
      child: FutureBuilder<List<CameraMatch>>(
        future: _cameras,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const _Loading();
          final matches = snapshot.data!;
          if (matches.isEmpty) {
            return Text(
              'No public cameras are published near ${airport.displayCity}. '
              'Coverage today: ${CctvService.coverage.join(', ')}.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Road and weather cameras near the airport — see conditions before you land.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => SizedBox(
                    width: 260,
                    child: GestureDetector(
                      onTap: () => showCameraDialog(context, matches[i].camera, distanceKm: matches[i].distanceKm),
                      child: LiveCameraView(camera: matches[i].camera, distanceKm: matches[i].distanceKm),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── News ────────────────────────────────────────────────────────────────

  Widget _newsSection(AirportInfoRecord airport, ColorScheme cs) {
    return _Section(
      title: 'Local news',
      icon: Icons.article_outlined,
      child: FutureBuilder<List<NewsArticle>>(
        future: _news,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const _Loading();
          final articles = snapshot.data!.take(5).toList();
          if (articles.isEmpty) {
            return Text('No recent headlines found.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13));
          }
          return Column(
            children: [
              for (final a in articles)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([a.source, if (a.published != null) timeago.format(a.published!)].join(' · ')),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: a.url.isEmpty ? null : () => launchUrl(Uri.parse(a.url), mode: LaunchMode.externalApplication),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Disruptions ─────────────────────────────────────────────────────────

  Widget _disruptionSection(AirportInfoRecord airport, ColorScheme cs) {
    return FutureBuilder(
      future: Future.wait([_quakes!, _fires!]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final quakes = snapshot.data![0] as List<Earthquake>;
        final fires = snapshot.data![1] as List<List>;
        final bigFires = fires.where((f) => (f[2] as num) >= 50).length;
        if (quakes.isEmpty && fires.isEmpty) return const SizedBox.shrink();
        return _Section(
          title: 'Possible disruptions nearby',
          icon: Icons.warning_amber_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final q in quakes)
                Text('Magnitude ${q.magnitude.toStringAsFixed(1)} earthquake · ${q.place} · ${timeago.format(q.time)}',
                    style: const TextStyle(fontSize: 13)),
              if (fires.isNotEmpty)
                Text(
                  '${fires.length} active fire detections within ~100 km in the last day'
                  '${bigFires > 0 ? ', $bigFires of them intense' : ''} (NASA FIRMS)',
                  style: const TextStyle(fontSize: 13),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Night sky ───────────────────────────────────────────────────────────

  Widget _skySection(AirportInfoRecord airport, ColorScheme cs) {
    return FutureBuilder<IssPass?>(
      future: _iss,
      builder: (context, snapshot) {
        final pass = snapshot.data;
        if (pass == null) return const SizedBox.shrink();
        return _Section(
          title: 'Look up',
          icon: Icons.satellite_alt,
          child: Text(
            'The International Space Station passes over ${airport.displayCity} '
            '${DateFormat('EEE').add_jm().format(pass.peak)} (your time), reaching '
            '${pass.maxElevationDeg.round()}° above the horizon.',
            style: const TextStyle(fontSize: 13),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget child;
  const _Section({required this.title, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: cs.secondary), const SizedBox(width: 8)],
                Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2));
}
