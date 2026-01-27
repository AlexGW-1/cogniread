import 'package:cogniread/src/features/library/data/library_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SyncStatusSnapshot serializes and restores state', () {
    final snapshot = SyncStatusSnapshot(
      at: DateTime.utc(2025, 1, 2, 3, 4, 5),
      state: SyncStatusState.paused,
      summary: 'Paused',
    );
    final map = snapshot.toMap();
    final restored = SyncStatusSnapshot.fromMap(map);
    expect(restored, isNotNull);
    expect(restored!.state, SyncStatusState.paused);
    expect(restored.summary, 'Paused');
  });

  test('SyncStatusSnapshot accepts legacy ok field', () {
    final mapSuccess = <String, Object?>{
      'at': '2025-01-02T03:04:05Z',
      'ok': true,
      'summary': 'OK',
    };
    final success = SyncStatusSnapshot.fromMap(mapSuccess);
    expect(success, isNotNull);
    expect(success!.state, SyncStatusState.success);

    final mapError = <String, Object?>{
      'at': '2025-01-02T03:04:05Z',
      'ok': false,
      'summary': 'Err',
    };
    final error = SyncStatusSnapshot.fromMap(mapError);
    expect(error, isNotNull);
    expect(error!.state, SyncStatusState.error);
  });
}
