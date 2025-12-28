import 'dart:io';
import 'dart:math';

import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStorageService implements StorageService {
  AppStorageService({this.booksDirectoryName = 'books'});

  final String booksDirectoryName;

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
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file does not exist', sourcePath);
    }

    final dirPath = await appStoragePath();
    final ext = p.extension(sourcePath);
    final base = _sanitize(p.basenameWithoutExtension(sourcePath));
    final safeBase = base.isEmpty ? 'book' : base;

    final targetPath = await _uniqueTargetPath(dirPath, safeBase, ext);
    final tempPath = _tempPath(dirPath, safeBase, ext);

    await _copyToTemp(sourceFile, tempPath);
    await File(tempPath).rename(targetPath);
    return targetPath;
  }

  Future<void> _copyToTemp(File source, String tempPath) async {
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    final sink = tempFile.openWrite();
    try {
      await source.openRead().pipe(sink);
    } finally {
      await sink.close();
    }
  }

  Future<String> _uniqueTargetPath(
    String dirPath,
    String base,
    String ext,
  ) async {
    final initialPath = p.join(dirPath, '$base$ext');
    if (!await File(initialPath).exists()) {
      return initialPath;
    }

    for (var i = 0; i < 50; i++) {
      final suffix = _uniqueSuffix();
      final candidate = p.join(dirPath, '${base}_$suffix$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
    }

    throw FileSystemException('Failed to allocate unique filename', dirPath);
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
