import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:cogniread/src/core/types/toc.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:cogniread/src/features/reader/presentation/reader_controller.dart';
import 'package:cogniread/src/features/library/data/library_store.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.bookId,
    this.embedded = false,
  });

  final String bookId;
  final bool embedded;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  late final ReaderController _controller;
  late final VoidCallback _controllerListener;
  ReadingPosition? _initialPosition;
  Timer? _positionDebounce;
  bool _didRestore = false;
  int _restoreAttempts = 0;
  double _viewportExtent = 0;

  @override
  void initState() {
    super.initState();
    _controller = ReaderController();
    _controllerListener = () {
      if (!mounted) {
        return;
      }
      setState(() {
        _initialPosition ??= _controller.initialPosition;
      });
      _scheduleRestorePosition();
    };
    _controller.addListener(_controllerListener);
    _itemPositionsListener.itemPositions.addListener(_onScroll);
    _controller.load(widget.bookId);
  }

  @override
  void dispose() {
    _positionDebounce?.cancel();
    _persistReadingPosition();
    _controller.removeListener(_controllerListener);
    _controller.dispose();
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_controller.loading || _controller.chapters.isEmpty) {
      return;
    }
    _positionDebounce?.cancel();
    _positionDebounce = Timer(
      const Duration(milliseconds: 500),
      _persistReadingPosition,
    );
  }

  void _scheduleRestorePosition() {
    if (_didRestore || _initialPosition == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreReadingPosition();
    });
  }

  void _restoreReadingPosition() {
    if (_didRestore || _initialPosition == null) {
      return;
    }
    if (!_itemScrollController.isAttached) {
      _retryRestore();
      return;
    }
    final index = _resolveChapterIndex(_initialPosition!);
    if (index == null ||
        index < 0 ||
        index >= _controller.chapters.length) {
      _didRestore = true;
      return;
    }
    final itemIndex = _itemIndexForChapter(index);
    if (itemIndex == null) {
      _didRestore = true;
      return;
    }
    _itemScrollController.jumpTo(index: itemIndex);
    final offsetWithin = _initialPosition?.offset ?? 0;
    if (offsetWithin > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_itemScrollController.isAttached) {
          _retryRestore();
          return;
        }
        _scrollOffsetController.animateScroll(
          offset: offsetWithin.toDouble(),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        );
      });
    }
    _didRestore = true;
  }

  void _retryRestore() {
    _restoreAttempts += 1;
    if (_restoreAttempts > 5) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreReadingPosition();
    });
  }

  int? _resolveChapterIndex(ReadingPosition position) {
    final chapterHref = position.chapterHref;
    if (chapterHref == null || chapterHref.isEmpty) {
      return null;
    }
    if (chapterHref.startsWith('index:')) {
      return int.tryParse(chapterHref.substring('index:'.length));
    }
    final index =
        _controller.chapters.indexWhere((chapter) => chapter.href == chapterHref);
    return index == -1 ? null : index;
  }

  Future<void> _persistReadingPosition() async {
    if (_controller.loading ||
        _controller.chapters.isEmpty ||
        _itemPositionsListener.itemPositions.value.isEmpty) {
      return;
    }
    final position = _computeReadingPosition();
    if (position == null) {
      return;
    }
    await _controller.saveReadingPosition(widget.bookId, position);
  }

  ReadingPosition? _computeReadingPosition() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return null;
    }
    final visible = positions.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final active = visible.firstWhere(
      (pos) => pos.itemLeadingEdge <= 0 && pos.itemTrailingEdge > 0,
      orElse: () => visible.first,
    );
    final currentItemIndex = active.index;

    final chapterIndex = currentItemIndex;
    if (chapterIndex < 0 || chapterIndex >= _controller.chapters.length) {
      return null;
    }
    final chapter = _controller.chapters[chapterIndex];
    final chapterHref = chapter.href ?? 'index:$chapterIndex';
    final offsetWithin = _viewportExtent <= 0
        ? 0
        : (-active.itemLeadingEdge * _viewportExtent).round();
    return ReadingPosition(
      chapterHref: chapterHref,
      anchor: null,
      offset: offsetWithin < 0 ? 0 : offsetWithin,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasToc = _controller.chapters.length > 1;
    final body = _buildBody(context);
    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_controller.title ?? 'Reader'),
        actions: [
          IconButton(
            tooltip: 'Оглавление',
            onPressed: hasToc ? _showToc : null,
            key: const ValueKey('reader-toc-button'),
            icon: const Icon(Icons.list),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasToc = _controller.chapters.length > 1;
    final readerSurface = scheme.surface.withAlpha(242);
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: readerSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: _controller.loading
              ? const Center(child: CircularProgressIndicator())
              : _controller.error != null
                  ? _ReaderErrorPanel(
                      message: _controller.error!,
                      onRetry: () {
                        _controller.retry();
                      },
                    )
                  : _controller.chapters.isEmpty
                      ? const Center(
                          child: Text('Нет данных для отображения'),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ReaderHeader(
                              title: _controller.title ?? 'Reader',
                              hasToc: hasToc,
                              onTocTap: _showToc,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  _viewportExtent = constraints.maxHeight;
                                  return SelectionArea(
                                    child: ScrollablePositionedList.builder(
                                      itemScrollController:
                                          _itemScrollController,
                                      itemPositionsListener:
                                          _itemPositionsListener,
                                      scrollOffsetController:
                                          _scrollOffsetController,
                                      itemCount: _controller.chapters.length,
                                      itemBuilder: (context, index) {
                                        final chapter =
                                            _controller.chapters[index];
                                        return _ChapterContent(
                                          chapter: chapter,
                                          dividerColor: scheme.outlineVariant,
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
    final wrapped = widget.embedded ? content : SafeArea(child: content);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.surfaceContainerHighest.withAlpha(64),
            scheme.surface.withAlpha(13),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: wrapped,
    );
  }

  void _showToc() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final hasGenerated = _controller.hasGeneratedToc;
            final mode = _controller.tocMode;
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Оглавление',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _exportToc,
                          child: const Text('Экспорт'),
                        ),
                      ],
                    ),
                  ),
                  if (hasGenerated)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<TocMode>(
                            segments: const [
                              ButtonSegment(
                                value: TocMode.official,
                                label: Text('Официальное'),
                              ),
                              ButtonSegment(
                                value: TocMode.generated,
                                label: Text('Сгенерированное'),
                              ),
                            ],
                            selected: {mode},
                            onSelectionChanged: (selection) {
                              _controller.setTocMode(selection.first);
                            },
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Режим может быть убран в будущем.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _controller.chapters.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final chapter = _controller.chapters[index];
                        final indent = 16.0 + (chapter.level * 18.0);
                        return ListTile(
                          contentPadding: EdgeInsets.only(
                            left: indent,
                            right: 16,
                            top: 4,
                            bottom: 4,
                          ),
                          title: Text(chapter.title),
                          onTap: () {
                            Navigator.of(context).pop();
                            _scrollToChapter(index);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportToc() async {
    if (_controller.chapters.isEmpty) {
      return;
    }
    final buffer = StringBuffer();
    for (final chapter in _controller.chapters) {
      final indent = '  ' * chapter.level;
      buffer.writeln('$indent${chapter.title}');
    }
    final safeTitle = _sanitizeFileName(_controller.title ?? 'toc');
    final fileName = 'cogniread_toc_$safeTitle.txt';
    final appSupport = await getApplicationSupportDirectory();
    var writtenPath = '';
    Future<bool> tryWrite(String path) async {
      try {
        await File(path).writeAsString(buffer.toString());
        return true;
      } catch (e) {
        Log.d('TOC export failed: $path ($e)');
        return false;
      }
    }

    final candidates = <String>[
      p.join(appSupport.path, fileName),
      p.join(Directory.systemTemp.path, fileName),
    ];

    for (final candidate in candidates) {
      if (await tryWrite(candidate)) {
        writtenPath = candidate;
        break;
      }
    }

    if (writtenPath.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось экспортировать оглавление.')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Оглавление экспортировано: $writtenPath')),
    );
  }

  String _sanitizeFileName(String value) {
    final cleaned =
        value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').trim();
    return cleaned.isEmpty ? 'toc' : cleaned;
  }

  void _scrollToChapter(int index) {
    if (index < 0 || index >= _controller.chapters.length) {
      return;
    }
    final itemIndex = _itemIndexForChapter(index);
    if (itemIndex == null) {
      return;
    }
    _itemScrollController.scrollTo(
      index: itemIndex,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  int? _itemIndexForChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _controller.chapters.length) {
      return null;
    }
    return chapterIndex;
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
    );
  }
}

class _ReaderErrorPanel extends StatelessWidget {
  const _ReaderErrorPanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterContent extends StatelessWidget {
  const _ChapterContent({
    required this.chapter,
    required this.dividerColor,
  });

  final ReaderChapter chapter;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: _ChapterHeader(
              title: chapter.title,
            ),
          ),
          for (final paragraph in chapter.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                paragraph,
                textAlign: TextAlign.justify,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.65,
                  fontFamily: 'Georgia',
                  fontFamilyFallback: [
                    'Times New Roman',
                    'Times',
                    'serif',
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 32,
              color: dividerColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.title,
    required this.hasToc,
    required this.onTocTap,
  });

  final String title;
  final bool hasToc;
  final VoidCallback onTocTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Оглавление',
          onPressed: hasToc ? onTocTap : null,
          key: const ValueKey('reader-toc-button-inline'),
          icon: Icon(Icons.list, color: scheme.primary),
        ),
      ],
    );
  }
}
