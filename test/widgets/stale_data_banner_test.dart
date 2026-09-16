import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/config/app_config.dart';
import 'package:skypulse/screens/widgets/stale_data_banner.dart';

Future<void> _pump(WidgetTester tester, DateTime lastUpdated) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: StaleDataBanner(lastUpdated: lastUpdated))),
  );
}

void main() {
  testWidgets('stays hidden while data is fresh', (tester) async {
    await _pump(tester, DateTime.now().subtract(const Duration(minutes: 5)));
    expect(find.byIcon(Icons.cloud_off), findsNothing);
  });

  testWidgets('warns once data passes the stale threshold', (tester) async {
    await _pump(
      tester,
      DateTime.now().subtract(
        Duration(minutes: AppConfig.staleDataThresholdMinutes + 15),
      ),
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.textContaining('45 minutes old'), findsOneWidget);
  });

  testWidgets('does not warn exactly at the threshold', (tester) async {
    await _pump(
      tester,
      DateTime.now().subtract(
        Duration(minutes: AppConfig.staleDataThresholdMinutes),
      ),
    );
    expect(find.byIcon(Icons.cloud_off), findsNothing);
  });
}
