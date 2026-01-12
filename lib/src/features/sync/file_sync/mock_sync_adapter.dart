import 'sync_adapter.dart';

class MockSyncAdapter implements SyncAdapter {
  MockSyncAdapter({this.failWith});

  final SyncAdapterException? failWith;
  final Map<String, SyncFile> _files = <String, SyncFile>{};

  void seedFile(String path, List<int> bytes) {
    final ref = SyncFileRef(
      path: path,
      updatedAt: DateTime.now().toUtc(),
      size: bytes.length,
    );
    _files[path] = SyncFile(ref: ref, bytes: bytes);
  }

  @override
  Future<List<SyncFileRef>> listFiles() async {
    _maybeThrow();
    return _files.values.map((file) => file.ref).toList();
  }

  @override
  Future<SyncFile?> getFile(String path) async {
    _maybeThrow();
    return _files[path];
  }

  @override
  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    _maybeThrow();
    final ref = SyncFileRef(
      path: path,
      updatedAt: DateTime.now().toUtc(),
      size: bytes.length,
    );
    _files[path] = SyncFile(ref: ref, bytes: bytes);
  }

  @override
  Future<void> deleteFile(String path) async {
    _maybeThrow();
    _files.remove(path);
  }

  void _maybeThrow() {
    if (failWith != null) {
      throw failWith!;
    }
  }
}
