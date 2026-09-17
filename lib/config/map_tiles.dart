import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'app_config.dart';

/// Basemap tile configuration.
///
/// The app hard-coded CARTO's raster basemaps, which now require an API key:
/// every tile comes back stamped "API KEY REQUIRED · carto.com/basemaps/apikey"
/// across the middle. That watermark covered both maps in the app.
///
/// OpenStreetMap's standard tiles need no key and are the default, so the maps
/// work out of the box. Supply `CARTO_API_KEY` in `.env` to get CARTO's dark
/// and light themes instead, which suit the app's palette better.
class MapTiles {
  MapTiles._();

  /// OSM's tile usage policy requires a genuine identifying User-Agent.
  static const userAgentPackageName = 'com.skypulse.skypulse';

  static bool get hasCartoKey => AppConfig.cartoApiKey.isNotEmpty;

  static String urlTemplate({required bool isDark}) {
    if (hasCartoKey) {
      final style = isDark ? 'dark_all' : 'light_all';
      return 'https://{s}.basemaps.cartocdn.com/$style/{z}/{x}/{y}@2x.png'
          '?api_key=${AppConfig.cartoApiKey}';
    }
    // Keyless fallback. OSM serves one standard style, so this looks the same
    // in light and dark mode.
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  static List<String> get subdomains =>
      hasCartoKey ? const ['a', 'b', 'c', 'd'] : const [];

  /// Attribution required by whichever provider is actually in use.
  static Widget attribution() {
    return RichAttributionWidget(
      attributions: [
        const TextSourceAttribution('OpenStreetMap contributors'),
        if (hasCartoKey) const TextSourceAttribution('CARTO'),
      ],
    );
  }

  /// Esri World Imagery: keyless satellite basemap (attribution required).
  static TileLayer satelliteLayer() {
    return TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: userAgentPackageName,
      maxNativeZoom: 19,
    );
  }

  static Widget satelliteAttribution() {
    return const RichAttributionWidget(
      attributions: [
        TextSourceAttribution('Esri, Maxar, Earthstar Geographics'),
        TextSourceAttribution('OpenStreetMap contributors'),
      ],
    );
  }

  /// A ready-made tile layer for the current theme.
  static TileLayer layer({required bool isDark}) {
    return TileLayer(
      urlTemplate: urlTemplate(isDark: isDark),
      subdomains: subdomains,
      userAgentPackageName: userAgentPackageName,
      // OSM asks that clients not retry aggressively on failure.
      maxNativeZoom: 19,
    );
  }
}
