import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/airport_directory.dart';
import '../../services/radio_service.dart';

/// Lets a traveller pick a local radio station for their destination.
///
/// Returns the chosen station, or null if they skipped.
Future<RadioStation?> showRadioPicker(
  BuildContext context, {
  required AirportInfoRecord destination,
  String? currentUuid,
}) {
  return showModalBottomSheet<RadioStation>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => _RadioPicker(
        destination: destination,
        currentUuid: currentUuid,
        scroll: scroll,
      ),
    ),
  );
}

class _RadioPicker extends StatefulWidget {
  final AirportInfoRecord destination;
  final String? currentUuid;
  final ScrollController scroll;

  const _RadioPicker({required this.destination, required this.currentUuid, required this.scroll});

  @override
  State<_RadioPicker> createState() => _RadioPickerState();
}

class _RadioPickerState extends State<_RadioPicker> {
  late Future<List<RadioStation>> _stations;
  bool _newsOnly = false;

  @override
  void initState() {
    super.initState();
    _stations = _load();
  }

  Future<List<RadioStation>> _load() async {
    final d = widget.destination;
    // Widen the search if the immediate area has little coverage.
    var stations = await RadioService.instance.near(d.lat, d.lon, radiusKm: 60);
    if (stations.length < 5) {
      stations = await RadioService.instance.near(d.lat, d.lon, radiusKm: 250);
    }
    return stations;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final player = RadioPlayer.instance;

    return FutureBuilder<List<RadioStation>>(
      future: _stations,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <RadioStation>[];
        final shown = _newsOnly ? all.where((s) => s.looksLikeNews).toList() : all;

        return ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Radio in ${widget.destination.displayCity}',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Listen to local news and music before you land. Stations are geotagged internet streams '
              'from the Radio Browser directory, so some are online-only.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            FilterChip(
              label: const Text('News & talk only'),
              selected: _newsOnly,
              onSelected: (v) => setState(() => _newsOnly = v),
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _newsOnly
                      ? 'No news or talk stations are listed near ${widget.destination.displayCity}. Try all stations.'
                      : 'No playable stations are listed near ${widget.destination.displayCity} yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              for (final s in shown)
                ValueListenableBuilder<RadioStation?>(
                  valueListenable: player.current,
                  builder: (context, playing, _) {
                    final isPlaying = playing?.uuid == s.uuid;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton.filledTonal(
                        tooltip: isPlaying ? 'Stop preview' : 'Preview',
                        icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                        onPressed: () => isPlaying ? player.stop() : player.play(s),
                      ),
                      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (s.tags.isNotEmpty) s.tags.take(3).join(', '),
                          if (s.bitrate > 0) '${s.bitrate} kbps',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: widget.currentUuid == s.uuid
                          ? Chip(label: const Text('Chosen'), backgroundColor: cs.primary.withValues(alpha: 0.2))
                          : TextButton(onPressed: () => Navigator.pop(context, s), child: const Text('Choose')),
                    );
                  },
                ),
          ],
        );
      },
    );
  }
}
