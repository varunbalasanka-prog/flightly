import 'airport_directory.dart';
import 'data_gateway.dart';

/// A public road or weather camera published by a transport agency.
class PublicCamera {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final String imageUrl;
  final String provider;
  final String region;

  const PublicCamera({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.imageUrl,
    required this.provider,
    required this.region,
  });

  /// Adds a cache-busting parameter so a refresh fetches the newest frame.
  String frameUrl(DateTime at) {
    final sep = imageUrl.contains('?') ? '&' : '?';
    return '$imageUrl${sep}t=${at.millisecondsSinceEpoch ~/ 30000}';
  }
}

class CameraMatch {
  final PublicCamera camera;
  final double distanceKm;
  const CameraMatch(this.camera, this.distanceKm);
}

/// The combined camera catalog (~9,800 cameras across eight networks),
/// refreshed daily server-side by the `cctv-catalog` function.
///
/// Coverage is regional: London, California, Finland, British Columbia,
/// New South Wales, Ontario, Calgary and Austin. Elsewhere there are simply no
/// public cameras in the catalog, and callers must say so.
class CctvService {
  CctvService._();
  static final CctvService instance = CctvService._();

  static const coverage = [
    'London', 'California', 'Finland', 'British Columbia',
    'New South Wales', 'Ontario', 'Calgary', 'Austin',
  ];

  Cached<List<PublicCamera>>? _catalog;
  Future<List<PublicCamera>>? _loading;

  Future<List<PublicCamera>> catalog() {
    if (_catalog != null && _catalog!.fresherThan(const Duration(hours: 6))) {
      return Future.value(_catalog!.value);
    }
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<List<PublicCamera>> _load() async {
    final meta = await DataGateway.instance.function('cctv-catalog');
    final url = meta is Map ? meta['url'] as String? : null;
    if (url == null) return _catalog?.value ?? const [];

    final body = await DataGateway.instance.getJson(url, timeout: const Duration(seconds: 40));
    final rows = body is Map ? body['cameras'] as List? : null;
    if (rows == null) return _catalog?.value ?? const [];

    final cameras = <PublicCamera>[];
    for (final r in rows) {
      final row = r as List;
      cameras.add(PublicCamera(
        id: row[0] as String,
        name: row[1] as String,
        lat: (row[2] as num).toDouble(),
        lon: (row[3] as num).toDouble(),
        imageUrl: row[4] as String,
        provider: row[5] as String,
        region: row[6] as String,
      ));
    }
    _catalog = Cached(cameras);
    return cameras;
  }

  Future<List<CameraMatch>> nearest(double lat, double lon, {double radiusKm = 60, int limit = 12}) async {
    final all = await catalog();
    final hits = <CameraMatch>[];
    for (final c in all) {
      // Cheap bounding pre-filter before the trig.
      if ((c.lat - lat).abs() > radiusKm / 100 + 0.5) continue;
      final d = haversineKm(lat, lon, c.lat, c.lon);
      if (d <= radiusKm) hits.add(CameraMatch(c, d));
    }
    hits.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return hits.take(limit).toList();
  }
}
