import 'dart:io';
import 'dart:math';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStorageService implements StorageService {
  AppStorageService({
    this.booksDirectoryName = 'books',
    this.maxFileSizeBytes = 200 * 1024 * 1024,
  });

  final String booksDirectoryName;
  final int maxFileSizeBytes;

  @override
  Future<String> appStoragePath() async {
    final baseDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(baseDir.path, booksDirectoryName));
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
    return booksDir.path;
  }

  @override
  Future<String> copyToAppStorage(String sourcePath) async {
    final stored = await copyToAppStorageWithHash(sourcePath);
    return stored.path;
  }

  @override
  Future<StoredFile> copyToAppStorageWithHash(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file does not exist', sourcePath);
    }

    final resolvedPath = await sourceFile.resolveSymbolicLinks();
    final resolvedFile = File(resolvedPath);
    final stat = await resolvedFile.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Source path is not a file', resolvedPath);
    }

    final ext = p.extension(resolvedPath).toLowerCase();
    if (ext != '.epub') {
      throw FormatException('Unsupported file extension');
    }
    if (stat.size == 0) {
      throw FormatException('File is empty');
    }
    if (stat.size > maxFileSizeBytes) {
      throw FormatException('File is too large');
    }

    final dirPath = await appStoragePath();
    final base = _sanitize(p.basenameWithoutExtension(resolvedPath));
    final safeBase = base.isEmpty ? 'book' : base;

    final tempPath = _tempPath(dirPath, safeBase, ext);
    final hash = await _copyToTempWithHash(resolvedFile, tempPath, stat.size);

    final targetPath = _targetPath(dirPath, safeBase, ext, hash);
    if (await File(targetPath).exists()) {
      await File(tempPath).delete();
      return StoredFile(path: targetPath, hash: hash, alreadyExists: true);
    }

    await File(tempPath).rename(targetPath);
    return StoredFile(path: targetPath, hash: hash, alreadyExists: false);
  }

  Future<String> _copyToTempWithHash(
    File source,
    String tempPath,
    int expectedSize,
  ) async {
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    final sink = tempFile.openWrite();
    final hashSink = _HashSink();
    final hasher = sha256.startChunkedConversion(hashSink);
    final input = source.openRead();
    var bytesRead = 0;
    try {
      await for (final chunk in input) {
        hasher.add(chunk);
        sink.add(chunk);
        bytesRead += chunk.length;
      }
    } finally {
      hasher.close();
      await sink.close();
    }
    if (bytesRead != expectedSize) {
      throw FileSystemException('Failed to read full file', source.path);
    }
    return hashSink.digest.toString();
  }

  String _targetPath(String dirPath, String base, String ext, String hash) {
    return p.join(dirPath, '${base}_$hash$ext');
  }

  String _uniqueSuffix() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 20);
    return '${micros}_$rand';
  }

  String _tempPath(String dirPath, String base, String ext) {
    final suffix = _uniqueSuffix();
    return p.join(dirPath, '.$base.$suffix.tmp$ext');
  }

  String _sanitize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final isAsciiLetter = (rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122);
      final isDigit = rune >= 48 && rune <= 57;
      if (isAsciiLetter || isDigit || ch == '-' || ch == '_' || ch == '.') {
        buffer.write(ch);
      } else {
        buffer.write('_');
      }
    }
    return buffer.toString();
  }
}

class _HashSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
