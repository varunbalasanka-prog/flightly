import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// Shape drawn for a point on the World map.
enum GlyphShape { plane, helicopter, dot, square, diamond, ring }

/// One drawable, tappable point on the World map.
class WorldGlyph {
  final double lat;
  final double lon;
  final GlyphShape shape;
  final Color color;
  final double size;

  /// Heading in degrees for rotating shapes (planes).
  final double rotationDeg;

  /// The object this glyph represents, returned on tap.
  final Object payload;

  const WorldGlyph({
    required this.lat,
    required this.lon,
    required this.shape,
    required this.color,
    required this.payload,
    this.size = 6,
    this.rotationDeg = 0,
  });
}

/// Draws thousands of points in a single canvas pass.
///
/// A MarkerLayer builds one widget per point, which is unusable at the
/// ~13,000 aircraft in a worldwide snapshot. This paints directly, culls to the
/// visible area, and drops to plain dots when too many are on screen for
/// individual shapes to be legible anyway.
class WorldGlyphLayer extends StatelessWidget {
  final List<WorldGlyph> glyphs;
  final int detailLimit;

  const WorldGlyphLayer({super.key, required this.glyphs, this.detailLimit = 2500});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        size: Size(camera.size.x, camera.size.y),
        painter: _GlyphPainter(camera: camera, glyphs: glyphs, detailLimit: detailLimit),
      ),
    );
  }

  /// The glyph nearest to a tap, within [maxDistancePx], or null.
  static WorldGlyph? hitTest(MapCamera camera, Offset tap, List<WorldGlyph> glyphs, {double maxDistancePx = 22}) {
    WorldGlyph? best;
    var bestDistance = maxDistancePx * maxDistancePx;
    for (final g in glyphs) {
      final p = camera.latLngToScreenPoint(LatLng(g.lat, g.lon));
      final dx = p.x - tap.dx, dy = p.y - tap.dy;
      final d = dx * dx + dy * dy;
      if (d < bestDistance) {
        bestDistance = d;
        best = g;
      }
    }
    return best;
  }
}

class _GlyphPainter extends CustomPainter {
  final MapCamera camera;
  final List<WorldGlyph> glyphs;
  final int detailLimit;

  _GlyphPainter({required this.camera, required this.glyphs, required this.detailLimit});

  static final Path _plane = () {
    // Nose points up (north); drawn at unit scale around the origin.
    return Path()
      ..moveTo(0, -1.0)
      ..lineTo(0.16, -0.35)
      ..lineTo(0.95, 0.15)
      ..lineTo(0.95, 0.32)
      ..lineTo(0.16, 0.12)
      ..lineTo(0.12, 0.62)
      ..lineTo(0.38, 0.82)
      ..lineTo(0.38, 0.95)
      ..lineTo(0, 0.85)
      ..lineTo(-0.38, 0.95)
      ..lineTo(-0.38, 0.82)
      ..lineTo(-0.12, 0.62)
      ..lineTo(-0.16, 0.12)
      ..lineTo(-0.95, 0.32)
      ..lineTo(-0.95, 0.15)
      ..lineTo(-0.16, -0.35)
      ..close();
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final bounds = camera.visibleBounds;
    final latPad = (bounds.north - bounds.south) * 0.05;
    final lonPad = (bounds.east - bounds.west) * 0.05;

    final visible = <(Offset, WorldGlyph)>[];
    for (final g in glyphs) {
      if (g.lat < bounds.south - latPad || g.lat > bounds.north + latPad) continue;
      if (g.lon < bounds.west - lonPad || g.lon > bounds.east + lonPad) continue;
      visible.add((camera.getOffsetFromOrigin(LatLng(g.lat, g.lon)), g));
    }

    final simple = visible.length > detailLimit;
    final dots = <Color, List<Offset>>{};
    final fill = Paint()..style = PaintingStyle.fill;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.55);

    for (final (offset, g) in visible) {
      if (simple || g.shape == GlyphShape.dot) {
        (dots[g.color] ??= []).add(offset);
        continue;
      }
      fill.color = g.color;
      switch (g.shape) {
        case GlyphShape.plane:
          canvas.save();
          canvas.translate(offset.dx, offset.dy);
          canvas.rotate(g.rotationDeg * pi / 180);
          canvas.scale(g.size);
          canvas.drawPath(_plane, fill);
          canvas.restore();
        case GlyphShape.helicopter:
          canvas.drawCircle(offset, g.size * 0.55, fill);
          canvas.drawLine(offset.translate(-g.size, 0), offset.translate(g.size, 0), fill..strokeWidth = 1.4);
        case GlyphShape.square:
          final r = Rect.fromCenter(center: offset, width: g.size * 1.6, height: g.size * 1.6);
          canvas.drawRect(r, fill);
          canvas.drawRect(r, outline);
        case GlyphShape.diamond:
          final s = g.size;
          final path = Path()
            ..moveTo(offset.dx, offset.dy - s)
            ..lineTo(offset.dx + s, offset.dy)
            ..lineTo(offset.dx, offset.dy + s)
            ..lineTo(offset.dx - s, offset.dy)
            ..close();
          canvas.drawPath(path, fill);
          canvas.drawPath(path, outline);
        case GlyphShape.ring:
          canvas.drawCircle(offset, g.size, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = g.color);
          canvas.drawCircle(offset, g.size * 0.35, fill);
        case GlyphShape.dot:
          break;
      }
    }

    final dotPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = simple ? 2.6 : 5;
    dots.forEach((color, points) {
      dotPaint.color = color;
      canvas.drawPoints(PointMode.points, points, dotPaint);
    });
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => true;
}
