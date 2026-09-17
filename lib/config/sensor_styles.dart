import 'package:flutter/widgets.dart';

/// Map "sensor" looks, applied as colour matrices over the basemap.
///
/// These are stylistic filters, not real night-vision or thermal imagery —
/// the underlying map is the same everywhere.
enum SensorStyle {
  normal('Normal'),
  nightVision('Night vision'),
  thermal('Thermal'),
  noir('Noir');

  final String label;
  const SensorStyle(this.label);

  ColorFilter? get filter => switch (this) {
        SensorStyle.normal => null,
        // Luminance into a bright green channel, lifted blacks.
        SensorStyle.nightVision => const ColorFilter.matrix([
            0.10, 0.25, 0.05, 0, 0,
            0.35, 0.85, 0.20, 0, 25,
            0.05, 0.15, 0.05, 0, 0,
            0, 0, 0, 1, 0,
          ]),
        // Inverted luminance pushed toward a white-hot palette.
        SensorStyle.thermal => const ColorFilter.matrix([
            -0.30, -0.60, -0.10, 0, 290,
            -0.25, -0.50, -0.10, 0, 230,
            -0.15, -0.25, -0.05, 0, 150,
            0, 0, 0, 1, 0,
          ]),
        SensorStyle.noir => const ColorFilter.matrix([
            0.30, 0.59, 0.11, 0, -20,
            0.30, 0.59, 0.11, 0, -20,
            0.30, 0.59, 0.11, 0, -20,
            0, 0, 0, 1, 0,
          ]),
      };
}
