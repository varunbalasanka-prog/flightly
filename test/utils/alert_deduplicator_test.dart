import 'package:flutter_test/flutter_test.dart';
import 'package:skypulse/models/models.dart';
import 'package:skypulse/utils/alert_deduplicator.dart';

void main() {
  group('AlertDeduplicator', () {
    late AlertDeduplicator deduplicator;

    setUp(() {
      deduplicator = AlertDeduplicator(window: const Duration(milliseconds: 100));
    });

    test('shouldSend returns true for first alert', () {
      final alert = AlertEvent(
        id: '1',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.gateChange,
        metadata: {'new_gate': 'B2'},
        createdAt: DateTime.now(),
      );

      expect(deduplicator.shouldSend(alert), isTrue);
    });

    test('shouldSend returns false for duplicate alert within window', () {
      final alert1 = AlertEvent(
        id: '1',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.gateChange,
        metadata: {'new_gate': 'B2'},
        createdAt: DateTime.now(),
      );
      
      final alert2 = AlertEvent(
        id: '2',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.gateChange,
        metadata: {'new_gate': 'B2'},
        createdAt: DateTime.now(),
      );

      expect(deduplicator.shouldSend(alert1), isTrue);
      expect(deduplicator.shouldSend(alert2), isFalse);
    });

    test('shouldSend returns true for different gate', () {
      final alert1 = AlertEvent(
        id: '1',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.gateChange,
        metadata: {'new_gate': 'B2'},
        createdAt: DateTime.now(),
      );
      
      final alert2 = AlertEvent(
        id: '2',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.gateChange,
        metadata: {'new_gate': 'B3'},
        createdAt: DateTime.now(),
      );

      expect(deduplicator.shouldSend(alert1), isTrue);
      expect(deduplicator.shouldSend(alert2), isTrue);
    });

    test('shouldSend returns true after window expires', () async {
      final alert = AlertEvent(
        id: '1',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.gateChange,
        metadata: {'new_gate': 'B2'},
        createdAt: DateTime.now(),
      );

      expect(deduplicator.shouldSend(alert), isTrue);
      
      await Future.delayed(const Duration(milliseconds: 150));
      
      // Window is 100ms, so it should send again
      expect(deduplicator.shouldSend(alert), isTrue);
    });

    test('delay alerts are bucketed to 15 mins', () {
      final alert1 = AlertEvent(
        id: '1',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.departureDelay,
        metadata: {'delay_minutes': 20},
        createdAt: DateTime.now(),
      );
      
      // 20 and 25 are in the same 15-minute bucket (15)
      final alert2 = AlertEvent(
        id: '2',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.departureDelay,
        metadata: {'delay_minutes': 25},
        createdAt: DateTime.now(),
      );

      // 35 is in the next bucket (30)
      final alert3 = AlertEvent(
        id: '3',
        userId: 'user1',
        title: 'Test',
        body: 'Test body',
        flightId: 'f1',
        eventType: AlertEventType.departureDelay,
        metadata: {'delay_minutes': 35},
        createdAt: DateTime.now(),
      );

      expect(deduplicator.shouldSend(alert1), isTrue);
      expect(deduplicator.shouldSend(alert2), isFalse);
      expect(deduplicator.shouldSend(alert3), isTrue);
    });
  });
}
