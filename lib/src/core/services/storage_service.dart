abstract class StorageService {
  /// Returns a writable app-managed directory for persistent files.
  Future<String> appStoragePath();

  /// Copies a file into app-managed storage and returns the new path.
  Future<String> copyToAppStorage(String sourcePath);

  /// Copies a file into app-managed storage and returns path + content hash.
  Future<StoredFile> copyToAppStorageWithHash(String sourcePath);
}

class StoredFile {
  const StoredFile({
    required this.path,
    required this.hash,
    required this.alreadyExists,
  });

  final String path;
  final String hash;
  final bool alreadyExists;
}
