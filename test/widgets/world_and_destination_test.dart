import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:skypulse/blocs/flight/flight_bloc.dart';
import 'package:skypulse/models/models.dart';
import 'package:skypulse/screens/destination/destination_panel.dart';
import 'package:skypulse/services/airport_directory.dart';
import 'package:skypulse/screens/world/world_glyph_layer.dart';
import 'package:skypulse/screens/world/world_screen.dart';

class _MockFlightBloc extends MockBloc<FlightEvent, FlightState> implements FlightBloc {}

Flight _flight() => Flight(
      id: '00000000-0000-0000-0000-000000000001',
      flightNumber: 'EK500',
      airlineIata: 'EK',
      departureAirportIata: 'DXB',
      arrivalAirportIata: 'COK',
      scheduledDeparture: DateTime.now().add(const Duration(hours: 5)),
      scheduledArrival: DateTime.now().add(const Duration(hours: 9)),
    );

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));

  group('WorldGlyphLayer.hitTest', () {
    testWidgets('picks the nearest glyph within reach and ignores far taps', (tester) async {
      late MapCamera camera;
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: FlutterMap(
            options: const MapOptions(initialCenter: LatLng(51.5, -0.1), initialZoom: 8),
            children: [
              Builder(builder: (context) {
                camera = MapCamera.of(context);
                return const SizedBox.shrink();
              }),
            ],
          ),
        ),
      ));

      const near = WorldGlyph(lat: 51.5, lon: -0.1, shape: GlyphShape.plane, color: Colors.blue, payload: 'near');
      const far = WorldGlyph(lat: 52.5, lon: 1.5, shape: GlyphShape.plane, color: Colors.blue, payload: 'far');
      final centre = camera.latLngToScreenPoint(const LatLng(51.5, -0.1));

      final hit = WorldGlyphLayer.hitTest(camera, Offset(centre.x + 5, centre.y + 5), const [near, far]);
      expect(hit?.payload, 'near');
      expect(WorldGlyphLayer.hitTest(camera, const Offset(5, 5), const [near]), isNull);
    });

    testWidgets('paints a worldwide snapshot without throwing', (tester) async {
      final glyphs = [
        for (var i = 0; i < 13000; i++)
          WorldGlyph(
            lat: -60 + (i % 120),
            lon: -180 + (i % 360).toDouble(),
            shape: GlyphShape.plane,
            color: Colors.cyan,
            rotationDeg: (i * 7 % 360).toDouble(),
            payload: i,
          ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: FlutterMap(
          options: const MapOptions(initialCenter: LatLng(20, 0), initialZoom: 2),
          children: [WorldGlyphLayer(glyphs: glyphs)],
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(WorldGlyphLayer), findsOneWidget);
    });
  });

  testWidgets('World screen renders and degrades gracefully with no network', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bloc = _MockFlightBloc();
    whenListen(bloc, const Stream<FlightState>.empty(), initialState: FlightLoadSuccess([_flight()]));

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<FlightBloc>.value(value: bloc, child: const WorldScreen()),
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('World'), findsOneWidget);
    expect(find.byTooltip('Layers & map style'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Layers & map style'));
    await tester.pumpAndSettle();
    expect(find.text('Military installations'), findsOneWidget);
    expect(find.text('Radio stations'), findsOneWidget);
    expect(find.text('Public cameras'), findsOneWidget);

    // Dispose timers.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Destination panel resolves the airport and shows its sections', (tester) async {
    final bloc = _MockFlightBloc();
    whenListen(bloc, const Stream<FlightState>.empty(), initialState: FlightLoadSuccess([_flight()]));

    AirportDirectory.instance.loadFromJson(File('assets/data/airports.json').readAsStringSync());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlocProvider<FlightBloc>.value(
          value: bloc,
          child: SingleChildScrollView(child: DestinationPanel(flight: _flight())),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('KOCHI'), findsOneWidget);
    expect(find.text('Local radio'), findsOneWidget);
    expect(find.text('Live cameras'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
