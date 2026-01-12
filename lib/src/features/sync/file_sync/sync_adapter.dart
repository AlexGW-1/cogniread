class SyncAdapterException implements Exception {
  SyncAdapterException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'SyncAdapterException($code): $message';
}

class SyncFileRef {
  const SyncFileRef({
    required this.path,
    this.updatedAt,
    this.size,
  });

  final String path;
  final DateTime? updatedAt;
  final int? size;
}

class SyncFile {
  const SyncFile({
    required this.ref,
    required this.bytes,
    this.etag,
  });

  final SyncFileRef ref;
  final List<int> bytes;
  final String? etag;
}

abstract class SyncAdapter {
  Future<List<SyncFileRef>> listFiles();

  Future<SyncFile?> getFile(String path);

  Future<void> putFile(
    String path,
    List<int> bytes, {
    String? contentType,
  });

  Future<void> deleteFile(String path);
}
