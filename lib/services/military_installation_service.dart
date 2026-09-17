import 'data_gateway.dart';

/// A military site as mapped by OpenStreetMap volunteers.
///
/// Community mapping is incomplete by nature — many sites are unmapped or
/// deliberately vague — and the UI labels the layer that way.
class MilitaryInstallation {
  final String id;
  final String name;
  final double lat;
  final double lon;

  /// OSM `military=*` value (airfield, base, naval_base, barracks, range) or
  /// "area" for generic military land use.
  final String kind;
  final String? operator;
  final String? country;

  const MilitaryInstallation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.kind,
    this.operator,
    this.country,
  });

  String get kindLabel => switch (kind) {
        'airfield' => 'Military airfield',
        'naval_base' => 'Naval base',
        'barracks' => 'Barracks',
        'range' => 'Training range',
        'base' => 'Military base',
        _ => 'Military area',
      };
}

class MilitaryInstallationService {
  MilitaryInstallationService._();
  static final MilitaryInstallationService instance = MilitaryInstallationService._();

  /// The largest box the server will query, in square degrees. Callers should
  /// only load installations when zoomed in this far.
  static const maxAreaSqDeg = 64.0;

  final _cache = <String, Cached<List<MilitaryInstallation>>>{};

  Future<List<MilitaryInstallation>> inBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    // Snap to a 2-degree grid so small pans reuse the same cached query.
    double snapDown(double v) => (v / 2).floorToDouble() * 2;
    double snapUp(double v) => (v / 2).ceilToDouble() * 2;
    final s = snapDown(south).clamp(-90.0, 90.0);
    final w = snapDown(west).clamp(-180.0, 180.0);
    final n = snapUp(north).clamp(-90.0, 90.0);
    final e = snapUp(east).clamp(-180.0, 180.0);
    if ((n - s) * (e - w) > maxAreaSqDeg) return const [];

    final key = '$s,$w,$n,$e';
    final hit = _cache[key];
    if (hit != null && hit.fresherThan(const Duration(hours: 6))) return hit.value;

    final data = await DataGateway.instance.proxy(
      'military-installations',
      {'south': s, 'west': w, 'north': n, 'east': e},
      const Duration(seconds: 60),
    );
    final elements = data is Map ? data['elements'] as List? : null;
    if (elements == null) return hit?.value ?? const [];

    final sites = <MilitaryInstallation>[];
    final seenNames = <String>{};
    for (final el in elements.whereType<Map<String, dynamic>>()) {
      final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      final lat = (el['lat'] ?? (el['center'] as Map?)?['lat']) as num?;
      final lon = (el['lon'] ?? (el['center'] as Map?)?['lon']) as num?;
      if (lat == null || lon == null) continue;
      final name = (tags['name:en'] ?? tags['name'] ?? tags['official_name']) as String?;
      final kind = (tags['military'] as String?) ?? 'area';
      // Unnamed generic land-use polygons are numerous and meaningless on a map.
      if (name == null && kind == 'area') continue;
      final label = name ?? kind;
      if (!seenNames.add('$label@${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}')) continue;
      sites.add(MilitaryInstallation(
        id: '${el['type']}/${el['id']}',
        name: label,
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        kind: kind,
        operator: tags['operator'] as String?,
        country: tags['addr:country'] as String?,
      ));
    }
    _cache[key] = Cached(sites);
    return sites;
  }
}
