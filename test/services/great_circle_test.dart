import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/services/aviation_data_service.dart';

void main() {
  final service = AviationDataService.instance;

  group('great-circle path', () {
    // Regression: this used to interpolate lat/lon linearly with a cosmetic
    // sine bulge, putting the JFK-LHR midpoint hundreds of km off course.
    test('midpoint of JFK to LHR follows the real arc', () {
      final path = service.calculateGreatCircleCoordinates(
        40.6413, -73.7781, 51.4700, -0.4543,
        points: 2,
      );
      final mid = path[1];
      // Computed independently: the true midpoint is 52.217N, 41.303W.
      // The old linear interpolation put it at 46.06N, 48.23W -- roughly
      // 700 km off course.
      expect(mid[0], closeTo(52.217, 0.05));
      expect(mid[1], closeTo(-41.303, 0.05));
    });

    test('starts and ends exactly on the endpoints', () {
      final path = service.calculateGreatCircleCoordinates(
        40.6413, -73.7781, 51.4700, -0.4543,
        points: 10,
      );
      expect(path.first[0], closeTo(40.6413, 0.001));
      expect(path.first[1], closeTo(-73.7781, 0.001));
      expect(path.last[0], closeTo(51.4700, 0.001));
      expect(path.last[1], closeTo(-0.4543, 0.001));
    });

    test('crosses the antimeridian without wrapping the long way', () {
      // Tokyo to Los Angeles crosses 180 degrees.
      final path = service.calculateGreatCircleCoordinates(
        35.5494, 139.7798, 33.9416, -118.4085,
        points: 8,
      );
      // Every step should be a short hop; a wrong wrap produces a ~250 degree jump.
      for (var i = 1; i < path.length; i++) {
        var deltaLon = (path[i][1] - path[i - 1][1]).abs();
        if (deltaLon > 180) deltaLon = 360 - deltaLon;
        expect(deltaLon, lessThan(40));
      }
    });

    test('handles identical endpoints without producing NaN', () {
      final path = service.calculateGreatCircleCoordinates(
        51.47, -0.45, 51.47, -0.45,
        points: 4,
      );
      for (final point in path) {
        expect(point[0].isNaN, isFalse);
        expect(point[1].isNaN, isFalse);
      }
    });
  });
}
