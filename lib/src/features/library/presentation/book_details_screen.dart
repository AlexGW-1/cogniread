import 'dart:io';

import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:cogniread/src/features/ai/presentation/ai_panel.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:cogniread/src/features/library/presentation/library_controller.dart';
import 'package:cogniread/src/features/search/book_text_extractor.dart';
import 'package:flutter/material.dart';

class BookDetailsScreen extends StatefulWidget {
  const BookDetailsScreen({super.key, required this.book, this.aiConfig});

  final LibraryBookItem book;
  final AiConfig? aiConfig;

  static Future<void> show(
    BuildContext context, {
    required LibraryBookItem book,
    AiConfig? aiConfig,
  }) async {
    final isDesktop = MediaQuery.of(context).size.width >= 1000;
    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 820,
            height: 720,
            child: BookDetailsScreen(book: book, aiConfig: aiConfig),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailsScreen(book: book, aiConfig: aiConfig),
      ),
    );
  }

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  final LibraryStore _store = LibraryStore();
  late final BookTextExtractor _extractor;
  String? _contextText;
  bool _contextLoading = false;
  String? _contextError;

  @override
  void initState() {
    super.initState();
    _extractor = ReaderBookTextExtractor(store: _store);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = _BookCover(
      title: widget.book.title,
      coverPath: widget.book.coverPath,
      width: 96,
      height: 128,
      borderRadius: 16,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Детали книги')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cover,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.book.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (widget.book.author != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.book.author!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Добавлена ${_formatDate(widget.book.addedAt)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.outline),
                        ),
                        if (widget.book.isMissing) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Файл отсутствует',
                            style: TextStyle(color: scheme.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AiPanel(
                  title: 'AI по книге',
                  config: widget.aiConfig ?? const AiConfig(),
                  embedded: true,
                  scopes: [
                    AiScope(
                      type: AiScopeType.book,
                      id: widget.book.id,
                      label: 'Книга',
                    ),
                  ],
                  contextProvider: _loadBookContext,
                ),
              ),
              if (_contextLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Готовим контекст для AI…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              if (_contextError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _contextError!,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<AiContext> _loadBookContext(AiScope scope) async {
    if (_contextText != null) {
      return AiContext(text: _contextText!, title: widget.book.title);
    }
    setState(() {
      _contextLoading = true;
      _contextError = null;
    });
    try {
      await _store.init();
      final entry = await _store.getById(widget.book.id);
      if (entry == null) {
        throw StateError('Книга не найдена');
      }
      final chapters = await _extractor.extract(entry);
      final text = _assembleContext(chapters);
      _contextText = text;
      return AiContext(text: text, title: widget.book.title);
    } catch (error) {
      _contextError = error.toString();
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _contextLoading = false;
        });
      }
    }
  }

  String _assembleContext(List<ExtractedChapter> chapters) {
    const maxChars = 20000;
    const maxParagraphsPerChapter = 8;
    final buffer = StringBuffer();
    for (final chapter in chapters) {
      if (buffer.length >= maxChars) {
        break;
      }
      final title = chapter.title.trim();
      if (title.isNotEmpty) {
        buffer.writeln(title);
      }
      var count = 0;
      for (final paragraph in chapter.paragraphs) {
        final text = paragraph.trim();
        if (text.isEmpty) {
          continue;
        }
        if (buffer.length + text.length + 1 > maxChars) {
          return buffer.toString().trim();
        }
        buffer.writeln(text);
        count += 1;
        if (count >= maxParagraphsPerChapter) {
          break;
        }
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.title,
    required this.coverPath,
    this.width = 56,
    this.height = 72,
    this.borderRadius = 12,
  });

  final String title;
  final String? coverPath;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = title.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    if (coverPath != null) {
      final file = File(coverPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.file(
            file,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _BookCoverPlaceholder(
              initial: initial,
              scheme: scheme,
              width: width,
              height: height,
              borderRadius: borderRadius,
            ),
          ),
        );
      }
    }
    return _BookCoverPlaceholder(
      initial: initial,
      scheme: scheme,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

class _BookCoverPlaceholder extends StatelessWidget {
  const _BookCoverPlaceholder({
    required this.initial,
    required this.scheme,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final String initial;
  final ColorScheme scheme;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withAlpha(230),
            scheme.tertiaryContainer.withAlpha(204),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Text(
          initial.toUpperCase(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.year}';
}
