import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/radio_service.dart';

/// Compact now-playing bar for the app-wide radio player. Hidden when idle.
class RadioBar extends StatelessWidget {
  const RadioBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = RadioPlayer.instance;
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<RadioStation?>(
      valueListenable: player.current,
      builder: (context, station, _) {
        if (station == null) return const SizedBox.shrink();
        return ValueListenableBuilder<RadioPlaybackState>(
          valueListenable: player.state,
          builder: (context, state, _) {
            final error = player.error.value;
            return Material(
              color: cs.surfaceContainerHigh,
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    Icon(Icons.radio, color: cs.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            station.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            state == RadioPlaybackState.error
                                ? (error ?? 'Stream unavailable')
                                : state == RadioPlaybackState.loading
                                    ? 'Connecting...'
                                    : [station.state, station.countryCode]
                                        .where((s) => s.isNotEmpty)
                                        .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: state == RadioPlaybackState.error ? cs.error : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state == RadioPlaybackState.loading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      IconButton(
                        tooltip: state == RadioPlaybackState.playing ? 'Pause' : 'Play',
                        icon: Icon(state == RadioPlaybackState.playing ? Icons.pause : Icons.play_arrow),
                        onPressed: state == RadioPlaybackState.error ? () => player.play(station) : player.toggle,
                      ),
                    IconButton(tooltip: 'Stop', icon: const Icon(Icons.close), onPressed: player.stop),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
