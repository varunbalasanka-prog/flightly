import 'dart:math';

/// Is a looked-up route consistent with where the aircraft actually is?
///
/// adsbdb maps a callsign to its usual route, which is sometimes the wrong
/// leg — airlines reuse flight numbers, and multi-leg flights share one. When
/// the aircraft is broadcasting, reject a route that it is confidently not
/// flying rather than display the wrong one.
///
/// Ported from God's Eye View's routePlausible.js (MIT), adapted there from
/// skylight (MIT). Returns false ONLY when the route is confidently wrong;
/// missing data never rejects a route.
class RoutePlausibility {
  RoutePlausibility._();

  static const nearEndpointKm = 130.0;
  static const crossTrackLimitKm = 200.0;
  static const lowAltitudeFt = 12000.0;
  static const verticalTrendFpm = 400.0;
  static const localAirportKm = 150.0;

  static bool plausible({
    required double lat,
    required double lon,
    double? altitudeFt,
    double? verticalRateFpm,
    double? originLat,
    double? originLon,
    double? destLat,
    double? destLon,
  }) {
    final haveOrigin = originLat != null && originLon != null;
    final haveDest = destLat != null && destLon != null;
    if (!haveOrigin && !haveDest) return true;

    bool near(double pLat, double pLon) => greatCircleKm(lat, lon, pLat, pLon) < nearEndpointKm;

    // (a) Geographically consistent: near an endpoint, or roughly on the path.
    var geometryOk = (haveOrigin && near(originLat, originLon)) || (haveDest && near(destLat, destLon));
    if (!geometryOk && haveOrigin && haveDest) {
      geometryOk = crossTrackKm(lat, lon, originLat, originLon, destLat, destLon).abs() < crossTrackLimitKm;
    } else if (!geometryOk) {
      geometryOk = true; // one endpoint known and not near it: can't judge
    }
    if (!geometryOk) return false;

    // (b) Low and climbing hard should be near the origin; low and
    // descending hard should be near the destination.
    if (altitudeFt != null &&
        altitudeFt < lowAltitudeFt &&
        verticalRateFpm != null &&
        verticalRateFpm.abs() > verticalTrendFpm) {
      if (verticalRateFpm > 0 && haveOrigin && greatCircleKm(lat, lon, originLat, originLon) > localAirportKm) {
        return false;
      }
      if (verticalRateFpm < 0 && haveDest && greatCircleKm(lat, lon, destLat, destLon) > localAirportKm) {
        return false;
      }
    }
    return true;
  }

  static const _r = 6371.0;
  static const _d2r = pi / 180;

  static double greatCircleKm(double lat1, double lon1, double lat2, double lon2) {
    final dp = (lat2 - lat1) * _d2r;
    final dl = (lon2 - lon1) * _d2r;
    final a = pow(sin(dp / 2), 2) + cos(lat1 * _d2r) * cos(lat2 * _d2r) * pow(sin(dl / 2), 2);
    return _r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double bearingRad(double lat1, double lon1, double lat2, double lon2) {
    final p1 = lat1 * _d2r, p2 = lat2 * _d2r, dl = (lon2 - lon1) * _d2r;
    return atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl));
  }

  /// Signed distance of a point from the great circle through two others.
  static double crossTrackKm(double lat, double lon, double lat1, double lon1, double lat2, double lon2) {
    final d13 = greatCircleKm(lat1, lon1, lat, lon) / _r;
    final b13 = bearingRad(lat1, lon1, lat, lon);
    final b12 = bearingRad(lat1, lon1, lat2, lon2);
    return asin(sin(d13) * sin(b13 - b12)) * _r;
  }
}
