import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../services/cctv_service.dart';

/// A public camera frame that refreshes itself.
///
/// Uses the browser's own <img> element on web
/// ([WebHtmlElementStrategy.prefer]): camera servers don't send CORS headers,
/// and Flutter's default web image pipeline would be blocked by that.
class LiveCameraView extends StatefulWidget {
  final PublicCamera camera;
  final double? distanceKm;
  final Duration refreshEvery;
  final double aspectRatio;

  const LiveCameraView({
    super.key,
    required this.camera,
    this.distanceKm,
    this.refreshEvery = const Duration(seconds: 30),
    this.aspectRatio = 16 / 9,
  });

  @override
  State<LiveCameraView> createState() => _LiveCameraViewState();
}

class _LiveCameraViewState extends State<LiveCameraView> {
  late DateTime _frameTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _frameTime = DateTime.now();
    _timer = Timer.periodic(widget.refreshEvery, (_) {
      if (mounted) setState(() => _frameTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.camera;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: cs.surfaceContainerHighest),
                Image.network(
                  c.frameUrl(_frameTime),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (_, _, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_outlined, color: cs.onSurfaceVariant),
                        const SizedBox(height: 6),
                        Text('Camera offline', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE · refreshed ${timeago.format(_frameTime)}',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        Text(
          [
            c.provider,
            if (widget.distanceKm != null) '${widget.distanceKm!.toStringAsFixed(1)} km away',
          ].join(' · '),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

Future<void> showCameraDialog(BuildContext context, PublicCamera camera, {double? distanceKm}) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LiveCameraView(camera: camera, distanceKm: distanceKm, refreshEvery: const Duration(seconds: 15)),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        ),
      ),
    ),
  );
}
