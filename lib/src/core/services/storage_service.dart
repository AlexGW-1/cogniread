abstract class StorageService {
  /// Returns a writable app-managed directory for persistent files.
  Future<String> appStoragePath();

  /// Copies a file into app-managed storage and returns the new path.
  Future<String> copyToAppStorage(String sourcePath);
}
