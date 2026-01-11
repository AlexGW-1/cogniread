import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:cogniread/src/core/types/anchor.dart';
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
  int? _selectionChapterIndex;
  SelectedContentRange? _selectionRange;
  String? _selectionText;
  ReadingPosition? _initialPosition;
  Timer? _positionDebounce;
  bool _didRestore = false;
  int _restoreAttempts = 0;
  double _viewportExtent = 0;
  double? _textWidth;

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
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bookId != oldWidget.bookId) {
      _positionDebounce?.cancel();
      _persistReadingPositionFor(oldWidget.bookId);
      _initialPosition = null;
      _didRestore = false;
      _restoreAttempts = 0;
      _selectionChapterIndex = null;
      _selectionRange = null;
      _selectionText = null;
      _controller.load(widget.bookId);
    }
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

  void _onChapterSelectionChanged(
    int index,
    SelectedContentRange? range,
  ) {
    if (index < 0 || index >= _controller.chapters.length) {
      return;
    }
    if (range == null || range.startOffset == range.endOffset) {
      if (_selectionChapterIndex == index) {
        _clearSelectionSnapshot();
      }
      return;
    }
    final text = _chapterPlainText(index);
    final start = range.startOffset.clamp(0, text.length) as int;
    final end = range.endOffset.clamp(0, text.length) as int;
    if (start >= end) {
      _clearSelectionSnapshot();
      return;
    }
    _selectionChapterIndex = index;
    _selectionRange = SelectedContentRange(
      startOffset: start,
      endOffset: end,
    );
    _selectionText = text.substring(start, end);
  }

  void _clearSelectionSnapshot() {
    _selectionChapterIndex = null;
    _selectionRange = null;
    _selectionText = null;
  }

  String _chapterPlainText(int index) {
    final chapter = _controller.chapters[index];
    return <String>[chapter.title, ...chapter.paragraphs].join();
  }

  bool get _canHighlightSelection {
    final text = _selectionText;
    return _selectionChapterIndex != null &&
        _selectionRange != null &&
        text != null &&
        text.trim().isNotEmpty;
  }

  Future<void> _addHighlightFromSelection(
    SelectableRegionState selectableRegionState,
    String colorKey,
  ) async {
    if (!_canHighlightSelection) {
      return;
    }
    final chapterIndex = _selectionChapterIndex!;
    final range = _selectionRange!;
    final excerpt = _selectionText!.trim();
    final saved = await _controller.addHighlight(
      chapterIndex: chapterIndex,
      startOffset: range.startOffset,
      endOffset: range.endOffset,
      excerpt: excerpt,
      color: colorKey,
    );
    if (!mounted) {
      return;
    }
    selectableRegionState.clearSelection();
    selectableRegionState.hideToolbar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Highlight сохранен' : 'Не удалось создать highlight',
        ),
      ),
    );
  }

  Future<void> _addNoteFromSelection(
    SelectableRegionState selectableRegionState,
  ) async {
    if (!_canHighlightSelection) {
      return;
    }
    final chapterIndex = _selectionChapterIndex!;
    final range = _selectionRange!;
    final excerpt = _selectionText!.trim();
    var selectedColor = _markOptions.first;
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Новая заметка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Введите заметку',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _markOptions)
                    ChoiceChip(
                      label: Text(option.label),
                      selected: option.key == selectedColor.key,
                      avatar: _HighlightSwatch(color: option.color),
                      onSelected: (_) {
                        setState(() {
                          selectedColor = option;
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final noteText = controller.text;
    if (saved != true || noteText.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заметка не сохранена')),
      );
      return;
    }
    final stored = await _controller.addNote(
      chapterIndex: chapterIndex,
      startOffset: range.startOffset,
      endOffset: range.endOffset,
      excerpt: excerpt,
      text: noteText,
      color: selectedColor.key,
    );
    if (!mounted) {
      return;
    }
    selectableRegionState.clearSelection();
    selectableRegionState.hideToolbar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          stored ? 'Заметка сохранена' : 'Не удалось сохранить заметку',
        ),
      ),
    );
  }

  void _showHighlights() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final highlights = _controller.highlights;
            if (highlights.isEmpty) {
              return const SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Пока нет выделений.'),
                  ),
                ),
              );
            }
            return SafeArea(
              child: ListView.separated(
                itemCount: highlights.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final highlight = highlights[index];
                  final chapterIndex = _chapterIndexForHighlight(highlight);
                  final chapterTitle = chapterIndex == null
                      ? 'Неизвестная глава'
                      : _controller.chapters[chapterIndex].title;
                  final excerpt = highlight.excerpt.trim();
                  return ListTile(
                    title: Text(
                      excerpt.isEmpty ? '(без текста)' : excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(chapterTitle),
                    leading: _HighlightSwatch(
                      color: _highlightColorFor(highlight.color),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Удалить выделение',
                      onPressed: () async {
                        await _controller.removeHighlight(highlight.id);
                      },
                    ),
                    onTap: chapterIndex == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _scrollToHighlight(highlight);
                          },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showNotes() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final notes = _controller.notes;
            if (notes.isEmpty) {
              return const SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Пока нет заметок.'),
                  ),
                ),
              );
            }
            return SafeArea(
              child: ListView.separated(
                itemCount: notes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final note = notes[index];
                  final chapterIndex = _chapterIndexForNote(note);
                  final chapterTitle = chapterIndex == null
                      ? 'Неизвестная глава'
                      : _controller.chapters[chapterIndex].title;
                  final noteText = note.noteText.trim();
                  return ListTile(
                    title: Text(
                      noteText.isEmpty ? '(без текста)' : noteText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(chapterTitle),
                    leading: _HighlightSwatch(
                      color: _markColorFor(note.color),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Удалить заметку',
                      onPressed: () async {
                        await _controller.removeNote(note.id);
                      },
                    ),
                    onTap: chapterIndex == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _scrollToNote(note);
                          },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showNotesHighlights() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        var filter = _MarkFilter.all;
        return StatefulBuilder(
          builder: (context, setState) {
            final entries = _markEntries(filter);
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
                            'Заметки и выделения',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SegmentedButton<_MarkFilter>(
                          segments: const [
                            ButtonSegment(
                              value: _MarkFilter.all,
                              label: Text('Все'),
                            ),
                            ButtonSegment(
                              value: _MarkFilter.notes,
                              label: Text('Заметки'),
                            ),
                            ButtonSegment(
                              value: _MarkFilter.highlights,
                              label: Text('Выделения'),
                            ),
                          ],
                          selected: {filter},
                          onSelectionChanged: (selection) {
                            setState(() {
                              filter = selection.first;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(
                            child: Text('Пока нет заметок и выделений.'),
                          )
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return ListTile(
                                title: Text(
                                  entry.excerpt,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${entry.typeLabel} · ${_formatDateTime(entry.createdAt)}',
                                ),
                                leading: _HighlightSwatch(
                                  color: entry.color,
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  entry.onTap();
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

  int? _chapterIndexForHighlight(Highlight highlight) {
    final anchor = Anchor.parse(highlight.anchor);
    if (anchor == null) {
      return null;
    }
    final chapterHref = anchor.chapterHref;
    if (chapterHref.startsWith('index:')) {
      return int.tryParse(chapterHref.substring('index:'.length));
    }
    final index =
        _controller.chapters.indexWhere((chapter) => chapter.href == chapterHref);
    return index == -1 ? null : index;
  }

  int? _chapterIndexForNote(Note note) {
    final anchor = Anchor.parse(note.anchor);
    if (anchor == null) {
      return null;
    }
    final chapterHref = anchor.chapterHref;
    if (chapterHref.startsWith('index:')) {
      return int.tryParse(chapterHref.substring('index:'.length));
    }
    final index =
        _controller.chapters.indexWhere((chapter) => chapter.href == chapterHref);
    return index == -1 ? null : index;
  }

  void _scrollToHighlight(Highlight highlight) {
    final anchor = Anchor.parse(highlight.anchor);
    if (anchor == null) {
      return;
    }
    final chapterIndex = _chapterIndexForHighlight(highlight);
    if (chapterIndex == null) {
      return;
    }
    final offsetWithin = _estimateHighlightScrollOffset(
      highlight,
      chapterIndex,
    );
    if (offsetWithin == null || offsetWithin <= 0) {
      return;
    }
    if (!_itemScrollController.isAttached) {
      return;
    }
    _itemScrollController.jumpTo(index: chapterIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached) {
        return;
      }
      _scrollOffsetController.animateScroll(
        offset: offsetWithin,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
    });
  }

  void _scrollToNote(Note note) {
    final anchor = Anchor.parse(note.anchor);
    if (anchor == null) {
      return;
    }
    final chapterIndex = _chapterIndexForNote(note);
    if (chapterIndex == null) {
      return;
    }
    final offsetWithin = _estimateAnchorScrollOffset(
      chapterIndex,
      anchor.offset,
    );
    if (offsetWithin == null || offsetWithin <= 0) {
      return;
    }
    if (!_itemScrollController.isAttached) {
      return;
    }
    _itemScrollController.jumpTo(index: chapterIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached) {
        return;
      }
      _scrollOffsetController.animateScroll(
        offset: offsetWithin,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
    });
  }

  List<_MarkEntry> _markEntries(_MarkFilter filter) {
    final entries = <_MarkEntry>[];
    if (filter == _MarkFilter.all || filter == _MarkFilter.highlights) {
      for (final highlight in _controller.highlights) {
        final excerpt = highlight.excerpt.trim();
        entries.add(
          _MarkEntry(
            typeLabel: 'Выделение',
            excerpt: excerpt.isEmpty ? '(без текста)' : excerpt,
            createdAt: highlight.createdAt,
            color: _markColorFor(highlight.color),
            onTap: () => _scrollToHighlight(highlight),
          ),
        );
      }
    }
    if (filter == _MarkFilter.all || filter == _MarkFilter.notes) {
      for (final note in _controller.notes) {
        final excerpt = note.excerpt.trim();
        entries.add(
          _MarkEntry(
            typeLabel: 'Заметка',
            excerpt: excerpt.isEmpty ? '(без текста)' : excerpt,
            createdAt: note.createdAt,
            color: _markColorFor(note.color),
            onTap: () => _scrollToNote(note),
          ),
        );
      }
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  double? _estimateHighlightScrollOffset(
    Highlight highlight,
    int chapterIndex,
  ) {
    final anchor = Anchor.parse(highlight.anchor);
    if (anchor == null) {
      return null;
    }
    return _estimateAnchorScrollOffset(
      chapterIndex,
      anchor.offset,
    );
  }

  double? _estimateAnchorScrollOffset(
    int chapterIndex,
    int offset,
  ) {
    final chapter = _controller.chapters[chapterIndex];
    final textWidth = _textWidth;
    if (textWidth == null || textWidth <= 0) {
      return null;
    }
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        );
    const bodyStyle = TextStyle(
      fontSize: 17,
      height: 1.65,
      fontFamily: 'Georgia',
      fontFamilyFallback: [
        'Times New Roman',
        'Times',
        'serif',
      ],
    );
    final titleText = chapter.title;
    if (offset < titleText.length) {
      final titleHeight = _measureTextHeight(titleText, titleStyle, textWidth);
      final caretOffset =
          _measureCaretOffset(titleText, titleStyle, textWidth, offset);
      return 6 + caretOffset; // top padding
    }
    var remaining = offset - titleText.length;
    var accumulated = 6 +
        _measureTextHeight(titleText, titleStyle, textWidth) +
        10; // title padding
    for (final paragraph in chapter.paragraphs) {
      if (remaining <= paragraph.length) {
        final caretOffset =
            _measureCaretOffset(paragraph, bodyStyle, textWidth, remaining);
        return accumulated + caretOffset;
      }
      accumulated +=
          _measureTextHeight(paragraph, bodyStyle, textWidth) + 12;
      remaining -= paragraph.length;
    }
    return accumulated;
  }

  double _measureTextHeight(
    String text,
    TextStyle? style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: width);
    return painter.height;
  }

  double _measureCaretOffset(
    String text,
    TextStyle? style,
    double width,
    int offset,
  ) {
    final clamped = offset.clamp(0, text.length) as int;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: width);
    return painter.getOffsetForCaret(
      TextPosition(offset: clamped),
      Rect.zero,
    ).dy;
  }

  List<_HighlightRange> _highlightRangesForChapter(int chapterIndex) {
    final ranges = <_HighlightRange>[];
    for (final highlight in _controller.highlights) {
      final anchor = Anchor.parse(highlight.anchor);
      if (anchor == null) {
        continue;
      }
      final index = anchor.chapterHref.startsWith('index:')
          ? int.tryParse(anchor.chapterHref.substring('index:'.length))
          : _controller.chapters
              .indexWhere((chapter) => chapter.href == anchor.chapterHref);
      if (index != chapterIndex) {
        continue;
      }
      final start = anchor.offset;
      final end = highlight.endOffset ??
          (start + highlight.excerpt.trim().length);
      if (end <= start) {
        continue;
      }
      ranges.add(
        _HighlightRange(
          start: start,
          end: end,
          color: _highlightColorFor(highlight.color),
        ),
      );
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  Color _highlightColorFor(String key) {
    return _markColorFor(key);
  }

  Color _markColorFor(String key) {
    return _markOptions
        .firstWhere(
          (option) => option.key == key,
          orElse: () => _markOptions.first,
        )
        .color;
  }

  Future<void> _persistReadingPosition() async {
    await _persistReadingPositionFor(widget.bookId);
  }

  Future<void> _persistReadingPositionFor(String bookId) async {
    if (_controller.loading ||
        _controller.chapters.isEmpty ||
        _itemPositionsListener.itemPositions.value.isEmpty) {
      return;
    }
    final position = _computeReadingPosition();
    if (position == null) {
      return;
    }
    await _controller.saveReadingPosition(bookId, position);
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
            tooltip: 'Выделения',
            onPressed: _showHighlights,
            icon: const Icon(Icons.highlight_outlined),
          ),
          IconButton(
            tooltip: 'Заметки',
            onPressed: _showNotes,
            icon: const Icon(Icons.sticky_note_2_outlined),
          ),
          IconButton(
            tooltip: 'Заметки и выделения',
            onPressed: _showNotesHighlights,
            icon: const Icon(Icons.view_list_outlined),
          ),
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
                              onHighlightsTap: _showHighlights,
                              onNotesTap: _showNotes,
                              onMarksTap: _showNotesHighlights,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  _viewportExtent = constraints.maxHeight;
                                  _textWidth = constraints.maxWidth;
                                  return SelectionArea(
                                    contextMenuBuilder:
                                        (context, selectableRegionState) {
                                      final items = <ContextMenuButtonItem>[
                                        if (_canHighlightSelection)
                                          for (final option in _markOptions)
                                            ContextMenuButtonItem(
                                              label: 'Highlight · ${option.label}',
                                              onPressed: () {
                                                _addHighlightFromSelection(
                                                  selectableRegionState,
                                                  option.key,
                                                );
                                              },
                                            ),
                                        if (_canHighlightSelection)
                                          ContextMenuButtonItem(
                                            label: 'Note',
                                            onPressed: () {
                                              _addNoteFromSelection(
                                                selectableRegionState,
                                              );
                                            },
                                          ),
                                        ...selectableRegionState
                                            .contextMenuButtonItems,
                                      ];
                                      return AdaptiveTextSelectionToolbar
                                          .buttonItems(
                                        anchors: selectableRegionState
                                            .contextMenuAnchors,
                                        buttonItems: items,
                                      );
                                    },
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
                                          chapterIndex: index,
                                          onSelectionChanged:
                                              _onChapterSelectionChanged,
                                          highlightRanges:
                                              _highlightRangesForChapter(index),
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

String _formatDateTime(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month.${date.year} $hour:$minute';
}

enum _MarkFilter {
  all,
  notes,
  highlights,
}

class _MarkEntry {
  const _MarkEntry({
    required this.typeLabel,
    required this.excerpt,
    required this.createdAt,
    required this.color,
    required this.onTap,
  });

  final String typeLabel;
  final String excerpt;
  final DateTime createdAt;
  final Color color;
  final VoidCallback onTap;
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

class _ChapterContent extends StatefulWidget {
  const _ChapterContent({
    required this.chapter,
    required this.chapterIndex,
    required this.onSelectionChanged,
    required this.highlightRanges,
    required this.dividerColor,
  });

  final ReaderChapter chapter;
  final int chapterIndex;
  final void Function(int, SelectedContentRange?) onSelectionChanged;
  final List<_HighlightRange> highlightRanges;
  final Color dividerColor;

  @override
  State<_ChapterContent> createState() => _ChapterContentState();
}

class _ChapterContentState extends State<_ChapterContent> {
  late final SelectionListenerNotifier _selectionNotifier;

  @override
  void initState() {
    super.initState();
    _selectionNotifier = SelectionListenerNotifier();
    _selectionNotifier.addListener(_handleSelectionChanged);
  }

  @override
  void dispose() {
    _selectionNotifier.removeListener(_handleSelectionChanged);
    _selectionNotifier.dispose();
    super.dispose();
  }

  void _handleSelectionChanged() {
    if (!_selectionNotifier.registered) {
      return;
    }
    widget.onSelectionChanged(
      widget.chapterIndex,
      _selectionNotifier.selection.range,
    );
  }

  List<TextSpan> _buildSpans(
    String text,
    int baseOffset,
    TextStyle? style,
  ) {
    final ranges = widget.highlightRanges;
    if (ranges.isEmpty || text.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.end <= baseOffset || range.start >= baseOffset + text.length) {
        continue;
      }
      final localStart = (range.start - baseOffset).clamp(0, text.length) as int;
      final localEnd = (range.end - baseOffset).clamp(0, text.length) as int;
      if (localEnd <= cursor) {
        continue;
      }
      if (localStart > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, localStart), style: style),
        );
      }
      final highlightStart = localStart < cursor ? cursor : localStart;
      spans.add(
        TextSpan(
          text: text.substring(highlightStart, localEnd),
          style: style?.copyWith(
            backgroundColor: range.color.withAlpha(140),
          ),
        ),
      );
      cursor = localEnd;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        );
    const bodyStyle = TextStyle(
      fontSize: 17,
      height: 1.65,
      fontFamily: 'Georgia',
      fontFamilyFallback: [
        'Times New Roman',
        'Times',
        'serif',
      ],
    );
    final titleText = widget.chapter.title;
    final titleSpans = _buildSpans(titleText, 0, titleStyle);
    final paragraphOffsets = <int>[];
    var runningOffset = titleText.length;
    for (final paragraph in widget.chapter.paragraphs) {
      paragraphOffsets.add(runningOffset);
      runningOffset += paragraph.length;
    }
    return SelectionListener(
      selectionNotifier: _selectionNotifier,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Text.rich(
                TextSpan(children: titleSpans),
                textAlign: TextAlign.left,
              ),
            ),
            for (var i = 0; i < widget.chapter.paragraphs.length; i += 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text.rich(
                  TextSpan(
                    children: _buildSpans(
                      widget.chapter.paragraphs[i],
                      paragraphOffsets[i],
                      bodyStyle,
                    ),
                  ),
                  textAlign: TextAlign.justify,
                  style: bodyStyle,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 32,
                color: widget.dividerColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightRange {
  const _HighlightRange({
    required this.start,
    required this.end,
    required this.color,
  });

  final int start;
  final int end;
  final Color color;
}

class _HighlightOption {
  const _HighlightOption({
    required this.key,
    required this.label,
    required this.color,
  });

  final String key;
  final String label;
  final Color color;
}

const List<_HighlightOption> _markOptions = [
  _HighlightOption(
    key: 'yellow',
    label: 'Желтый',
    color: Color(0xFFFFF59D),
  ),
  _HighlightOption(
    key: 'green',
    label: 'Зеленый',
    color: Color(0xFFC8E6C9),
  ),
  _HighlightOption(
    key: 'pink',
    label: 'Розовый',
    color: Color(0xFFF8BBD0),
  ),
  _HighlightOption(
    key: 'blue',
    label: 'Голубой',
    color: Color(0xFFBBDEFB),
  ),
];

class _HighlightSwatch extends StatelessWidget {
  const _HighlightSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.title,
    required this.hasToc,
    required this.onTocTap,
    required this.onHighlightsTap,
    required this.onNotesTap,
    required this.onMarksTap,
  });

  final String title;
  final bool hasToc;
  final VoidCallback onTocTap;
  final VoidCallback onHighlightsTap;
  final VoidCallback onNotesTap;
  final VoidCallback onMarksTap;

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
        IconButton(
          tooltip: 'Выделения',
          onPressed: onHighlightsTap,
          icon: Icon(Icons.highlight_outlined, color: scheme.primary),
        ),
        IconButton(
          tooltip: 'Заметки',
          onPressed: onNotesTap,
          icon: Icon(Icons.sticky_note_2_outlined, color: scheme.primary),
        ),
        IconButton(
          tooltip: 'Заметки и выделения',
          onPressed: onMarksTap,
          icon: Icon(Icons.view_list_outlined, color: scheme.primary),
        ),
      ],
    );
  }
}
