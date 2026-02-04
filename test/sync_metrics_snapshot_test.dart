import 'package:cogniread/src/features/library/data/library_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SyncMetricsSnapshot serializes and restores', () {
    final snapshot = SyncMetricsSnapshot(
      at: DateTime.utc(2025, 2, 3, 4, 5, 6),
      durationMs: 1200,
      bytesUploaded: 1234,
      bytesDownloaded: 4321,
      filesUploaded: 3,
      filesDownloaded: 4,
      appliedEvents: 5,
      appliedState: 6,
      uploadedEvents: 7,
      booksUploaded: 1,
      booksDownloaded: 2,
      errorCountTotal: 9,
      errorCountConsecutive: 2,
      errorCode: 'webdav_401',
    );
    final map = snapshot.toMap();
    final restored = SyncMetricsSnapshot.fromMap(map);
    expect(restored, isNotNull);
    expect(restored!.durationMs, 1200);
    expect(restored.bytesUploaded, 1234);
    expect(restored.bytesDownloaded, 4321);
    expect(restored.filesUploaded, 3);
    expect(restored.filesDownloaded, 4);
    expect(restored.appliedEvents, 5);
    expect(restored.appliedState, 6);
    expect(restored.uploadedEvents, 7);
    expect(restored.booksUploaded, 1);
    expect(restored.booksDownloaded, 2);
    expect(restored.errorCountTotal, 9);
    expect(restored.errorCountConsecutive, 2);
    expect(restored.errorCode, 'webdav_401');
  });
}
