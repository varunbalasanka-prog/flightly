import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/services/weather_service.dart';
import 'package:skypulse/utils/aircraft_classifier.dart';
import 'package:skypulse/utils/motion_model.dart';
import 'package:skypulse/utils/route_plausibility.dart';

void main() {
  group('RoutePlausibility', () {
    // JFK -> LHR
    const oLat = 40.64, oLon = -73.78, dLat = 51.47, dLon = -0.46;

    test('accepts an aircraft mid-Atlantic on the route', () {
      expect(
        RoutePlausibility.plausible(
          lat: 52.2, lon: -41.3, altitudeFt: 37000,
          originLat: oLat, originLon: oLon, destLat: dLat, destLon: dLon,
        ),
        isTrue,
      );
    });

    test('rejects a route when the aircraft is over Australia', () {
      expect(
        RoutePlausibility.plausible(
          lat: -33.9, lon: 151.2, altitudeFt: 30000,
          originLat: oLat, originLon: oLon, destLat: dLat, destLon: dLon,
        ),
        isFalse,
      );
    });

    test('rejects a low, climbing aircraft far from the claimed origin', () {
      // Just departed Paris, but the route says it left JFK.
      expect(
        RoutePlausibility.plausible(
          lat: 49.1, lon: 2.6, altitudeFt: 5000, verticalRateFpm: 2500,
          originLat: oLat, originLon: oLon, destLat: 49.0, destLon: 2.55,
        ),
        isFalse,
      );
    });

    test('never rejects without coordinates', () {
      expect(RoutePlausibility.plausible(lat: 0, lon: 0), isTrue);
    });
  });

  group('AircraftClassifier', () {
    test('uses type designators first', () {
      expect(AircraftClassifier.classify(typeCode: 'B77W'), AircraftClass.widebody);
      expect(AircraftClassifier.classify(typeCode: 'A388'), AircraftClass.quadjet);
      expect(AircraftClassifier.classify(typeCode: 'EC35'), AircraftClass.helicopter);
      expect(AircraftClassifier.classify(typeCode: 'AT76'), AircraftClass.turboprop);
    });

    test('falls back to the emitter category', () {
      expect(AircraftClassifier.classify(category: 'A7'), AircraftClass.helicopter);
      expect(AircraftClassifier.classify(category: 'B6'), AircraftClass.uav);
      expect(AircraftClassifier.classify(), AircraftClass.airliner);
    });
  });

  group('MotionModel', () {
    final t0 = DateTime(2026, 1, 1, 12);

    test('advances along the track at ground speed', () {
      // Due north at 360 kt for 10 s ~= 1.85 km ~= 0.0167 deg latitude.
      final p = MotionModel.predict(
        MotionFix(time: t0, lat: 50, lon: 0, trackDeg: 0, groundSpeedKt: 360),
        now: t0.add(const Duration(seconds: 10)),
      );
      expect(p.lat, closeTo(50.0167, 0.001));
      expect(p.lon, closeTo(0, 0.0001));
    });

    test('caps extrapolation when the signal is lost', () {
      final fix = MotionFix(time: t0, lat: 50, lon: 0, trackDeg: 90, groundSpeedKt: 450);
      final at45 = MotionModel.predict(fix, now: t0.add(const Duration(seconds: 45)));
      final at600 = MotionModel.predict(fix, now: t0.add(const Duration(minutes: 10)));
      expect(at600.lon, closeTo(at45.lon, 1e-9));
    });

    test('follows a turn instead of flying straight', () {
      final prev = MotionFix(time: t0, lat: 50, lon: 0, trackDeg: 0, groundSpeedKt: 250);
      final latest = MotionFix(time: t0.add(const Duration(seconds: 5)), lat: 50.006, lon: 0, trackDeg: 15, groundSpeedKt: 250);
      final p = MotionModel.predict(latest, previous: prev, now: latest.time.add(const Duration(seconds: 10)));
      expect(p.trackDeg, closeTo(45, 1)); // 3 deg/s for 10 s on top of 15
      expect(p.lon, greaterThan(0));
    });

    test('ignores implausible turn rates as noise', () {
      final prev = MotionFix(time: t0, lat: 50, lon: 0, trackDeg: 0, groundSpeedKt: 250);
      final latest = MotionFix(time: t0.add(const Duration(seconds: 2)), lat: 50, lon: 0, trackDeg: 170, groundSpeedKt: 250);
      expect(MotionModel.turnRate(prev, latest), 0);
    });
  });

  group('Metar parsing', () {
    test('derives ceiling, gusts and operational concerns', () {
      final m = Metar.fromJson({
        'icaoId': 'KJFK',
        'name': 'New York/John F Kennedy Intl, NY, US',
        'rawOb': 'KJFK 161251Z 21028G41KT 2SM TSRA BKN008 OVC015 20/18 A2990',
        'obsTime': 1789563060,
        'temp': 20, 'dewp': 18, 'wdir': 210, 'wspd': 28, 'visib': 2,
        'fltCat': 'IFR',
        'clouds': [
          {'cover': 'BKN', 'base': 800},
          {'cover': 'OVC', 'base': 1500},
        ],
      })!;
      expect(m.stationName, 'New York/John F Kennedy Intl');
      expect(m.ceilingFt, 800);
      expect(m.gustKt, 41);
      expect(m.operationalConcerns, containsAll([
        'Low cloud or visibility at KJFK (IFR)',
        'Strong winds at KJFK (41kt)',
        'Thunderstorms reported at KJFK',
      ]));
    });

    test('handles variable wind and 10+ visibility', () {
      final m = Metar.fromJson({'icaoId': 'EGLL', 'rawOb': 'EGLL VRB03KT 9999', 'wdir': 'VRB', 'visib': '6+'})!;
      expect(m.windDirDeg, isNull);
      expect(m.visibilitySm, 6);
      expect(m.operationalConcerns, isEmpty);
    });
  });
}
