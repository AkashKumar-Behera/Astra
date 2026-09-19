import 'package:flutter_test/flutter_test.dart';
import 'package:astra/core/services/location_rtdb_service.dart';

void main() {
  group('Location Freshness & Timestamp Evaluation', () {
    test('1. Null or zero timestamp evaluates to stale (not fresh)', () {
      expect(LocationRtdbService.isLocationFresh(null), isFalse);
      expect(LocationRtdbService.isLocationFresh(0), isFalse);
      expect(LocationRtdbService.isLocationFresh(-100), isFalse);
    });

    test('2. Recent timestamp within 3 minutes evaluates to Live (Fresh)', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final justNow = now - 10 * 1000; // 10 seconds ago
      final twoMinutesAgo = now - 2 * 60 * 1000; // 2 minutes ago

      expect(LocationRtdbService.isLocationFresh(justNow), isTrue);
      expect(LocationRtdbService.isLocationFresh(twoMinutesAgo), isTrue);
    });

    test('3. Timestamp older than 3 minutes evaluates to Stale / Last Known', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fourMinutesAgo = now - 4 * 60 * 1000; // 4 minutes ago
      final oneHourAgo = now - 60 * 60 * 1000; // 1 hour ago
      final oneDayAgo = now - 24 * 60 * 60 * 1000; // 1 day ago

      expect(LocationRtdbService.isLocationFresh(fourMinutesAgo), isFalse);
      expect(LocationRtdbService.isLocationFresh(oneHourAgo), isFalse);
      expect(LocationRtdbService.isLocationFresh(oneDayAgo), isFalse);
    });

    test('4. formatLocationFreshness produces honest human-readable labels', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      expect(
        LocationRtdbService.formatLocationFreshness(null),
        equals('Location unavailable'),
      );

      // Just now (< 1 min)
      expect(
        LocationRtdbService.formatLocationFreshness(now - 15 * 1000),
        equals('Live • Just now'),
      );

      // 2 mins ago (Live)
      expect(
        LocationRtdbService.formatLocationFreshness(now - 2 * 60 * 1000),
        equals('Live • 2m ago'),
      );

      // 5 mins ago (Last Known)
      expect(
        LocationRtdbService.formatLocationFreshness(now - 5 * 60 * 1000),
        equals('Last Known • 5m ago'),
      );

      // 3 hours ago (Last Known)
      expect(
        LocationRtdbService.formatLocationFreshness(now - 3 * 60 * 60 * 1000),
        equals('Last Known • 3h ago'),
      );

      // 2 days ago (Last Known)
      expect(
        LocationRtdbService.formatLocationFreshness(now - 48 * 60 * 60 * 1000),
        equals('Last Known • 2d ago'),
      );
    });

    test('5. LocationRefreshResult preserves freshness metadata without false live claims', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      const staleResult = LocationRefreshResult(
        isFresh: false,
        isSuccess: false,
        latitude: 28.6139,
        longitude: 77.2090,
        updatedAt: 1600000000000,
        statusLabel: 'Last Known • 5d ago',
      );

      expect(staleResult.isFresh, isFalse);
      expect(staleResult.isSuccess, isFalse);
      expect(staleResult.latitude, equals(28.6139));
      expect(staleResult.statusLabel, contains('Last Known'));

      final freshResult = LocationRefreshResult(
        isFresh: true,
        isSuccess: true,
        latitude: 28.6139,
        longitude: 77.2090,
        updatedAt: now,
        statusLabel: 'Live • Just now',
      );

      expect(freshResult.isFresh, isTrue);
      expect(freshResult.isSuccess, isTrue);
      expect(freshResult.statusLabel, contains('Live'));
    });
  });
}
