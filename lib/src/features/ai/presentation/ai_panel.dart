import 'dart:async';

import 'package:cogniread/src/features/ai/ai_models.dart';
import 'package:cogniread/src/features/ai/data/ai_artifact_store.dart';
import 'package:cogniread/src/features/ai/data/ai_service.dart';
import 'package:cogniread/src/features/ai/presentation/ai_controller.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AiPanel extends StatefulWidget {
  const AiPanel({
    super.key,
    required this.scopes,
    required this.contextProvider,
    required this.config,
    this.title,
    this.embedded = false,
  });

  final List<AiScope> scopes;
  final Future<AiContext> Function(AiScope scope) contextProvider;
  final AiConfig config;
  final String? title;
  final bool embedded;

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> with TickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _questionController;
  late final AiController _controller;
  AiScope? _activeScope;
  _AiRenderMode _renderMode = _AiRenderMode.auto;
  bool _initializing = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _questionController = TextEditingController();
    final service = _buildService(widget.config);
    _controller = AiController(
      config: widget.config,
      store: AiArtifactStore(),
      service: service,
      contextProvider: widget.contextProvider,
    );
    _controller.addListener(_onControllerChanged);
    _activeScope = widget.scopes.isNotEmpty ? widget.scopes.first : null;
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.init();
      final scope = _activeScope;
      if (scope != null) {
        await _controller.setScope(scope);
      }
    } catch (error) {
      Log.d('AI init failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _initializing = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant AiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      unawaited(_controller.refreshConfig(widget.config, reload: true));
    }
    if (!_sameScopes(oldWidget.scopes, widget.scopes)) {
      final nextScope = widget.scopes.isNotEmpty ? widget.scopes.first : null;
      _activeScope = nextScope;
      if (nextScope != null) {
        unawaited(_controller.setScope(nextScope));
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _questionController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  bool _sameScopes(List<AiScope> left, List<AiScope> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  AiService? _buildService(AiConfig config) {
    if (!config.isConfigured) {
      return null;
    }
    final base = Uri.tryParse(config.baseUrl!.trim());
    if (base == null) {
      return null;
    }
    return AiHttpService(baseUri: base, apiKey: config.apiKey);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.title ?? 'AI';
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: widget.embedded
              ? BorderRadius.circular(16)
              : const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.embedded)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!_controller.config.isConfigured)
                  Text(
                    'не настроено',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.error),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.scopes.length > 1)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.scopes
                    .map(
                      (scope) => ChoiceChip(
                        label: Text(scope.label),
                        selected: _activeScope == scope,
                        onSelected: (selected) {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _activeScope = scope;
                          });
                          unawaited(_controller.setScope(scope));
                        },
                      ),
                    )
                    .toList(),
              ),
            if (widget.scopes.length > 1) const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Сводка'),
                Tab(text: 'Вопросы'),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_AiRenderMode>(
                segments: const [
                  ButtonSegment(value: _AiRenderMode.auto, label: Text('Авто')),
                  ButtonSegment(
                    value: _AiRenderMode.markdown,
                    label: Text('Markdown'),
                  ),
                  ButtonSegment(
                    value: _AiRenderMode.text,
                    label: Text('Текст'),
                  ),
                ],
                selected: {_renderMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _renderMode = selection.first;
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildSummaryTab(context), _buildQaTab(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTab(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_controller.config.isConfigured) {
      return _AiEmptyState(
        message: 'AI не настроен. Укажите endpoint в настройках.',
        icon: Icons.auto_awesome_outlined,
      );
    }
    if (_controller.summaryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _controller.summaryError;
    if (error != null) {
      return _AiErrorState(
        message: error,
        onRetry: _controller.regenerateSummary,
      );
    }
    final summary = _controller.summary;
    if (summary == null || summary.content.trim().isEmpty) {
      return _AiEmptyState(
        message: 'Сводка еще не создана.',
        icon: Icons.notes_outlined,
        actionLabel: 'Сгенерировать',
        onAction: _controller.regenerateSummary,
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiMetaRow(
            label: 'Сводка',
            createdAt: summary.createdAt,
            model: summary.model,
          ),
          const SizedBox(height: 12),
          _AiContent(content: summary.content, mode: _renderMode),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _controller.regenerateSummary,
            icon: const Icon(Icons.refresh),
            label: const Text('Пересчитать'),
          ),
        ],
      ),
    );
  }

  Widget _buildQaTab(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_controller.config.isConfigured) {
      return _AiEmptyState(
        message: 'AI не настроен. Укажите endpoint в настройках.',
        icon: Icons.auto_awesome_outlined,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        TextField(
          controller: _questionController,
          textInputAction: TextInputAction.send,
          onSubmitted: _sendQuestion,
          decoration: InputDecoration(
            hintText: 'Спросить о тексте',
            suffixIcon: IconButton(
              onPressed: _sending ? null : () => _sendQuestion(null),
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ),
        ),
        if (_controller.qaError != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _controller.qaError!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _controller.qaItems.isEmpty
              ? _AiEmptyState(
                  message: 'Задайте вопрос, чтобы получить ответ.',
                  icon: Icons.question_answer_outlined,
                )
              : ListView.separated(
                  itemCount: _controller.qaItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _controller.qaItems[index];
                    return _AiQaCard(artifact: item, mode: _renderMode);
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _sendQuestion(String? value) async {
    final text = value ?? _questionController.text;
    if (text.trim().isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
    });
    try {
      await _controller.askQuestion(text);
    } catch (error) {
      Log.d('AI ask failed: $error');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
    });
    _questionController.clear();
  }
}

class _AiEmptyState extends StatelessWidget {
  const _AiEmptyState({
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiErrorState extends StatelessWidget {
  const _AiErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiMetaRow extends StatelessWidget {
  const _AiMetaRow({required this.label, required this.createdAt, this.model});

  final String label;
  final DateTime createdAt;
  final String? model;

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${createdAt.day.toString().padLeft(2, '0')}.'
        '${createdAt.month.toString().padLeft(2, '0')}.'
        '${createdAt.year}';
    final details = <String>[label, formatted];
    if (model != null && model!.trim().isNotEmpty) {
      details.add(model!.trim());
    }
    return Text(
      details.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _AiQaCard extends StatelessWidget {
  const _AiQaCard({required this.artifact, required this.mode});

  final AiArtifact artifact;
  final _AiRenderMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (artifact.prompt != null && artifact.prompt!.trim().isNotEmpty)
            Text(
              artifact.prompt!,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (artifact.prompt != null && artifact.prompt!.trim().isNotEmpty)
            const SizedBox(height: 8),
          _AiContent(content: artifact.content, mode: mode),
          const SizedBox(height: 8),
          _AiMetaRow(
            label: 'Ответ',
            createdAt: artifact.createdAt,
            model: artifact.model,
          ),
        ],
      ),
    );
  }
}

class _AiContent extends StatelessWidget {
  const _AiContent({required this.content, required this.mode});

  final String content;
  final _AiRenderMode mode;

  @override
  Widget build(BuildContext context) {
    final trimmed = content.trim();
    final shouldRenderMarkdown = switch (mode) {
      _AiRenderMode.markdown => true,
      _AiRenderMode.text => false,
      _AiRenderMode.auto => _looksLikeMarkdown(trimmed),
    };
    if (shouldRenderMarkdown) {
      return SelectionArea(
        child: MarkdownBody(
          data: trimmed,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
        ),
      );
    }
    return SelectableText(
      trimmed,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

enum _AiRenderMode { auto, markdown, text }

bool _looksLikeMarkdown(String text) {
  if (text.isEmpty) {
    return false;
  }
  if (text.contains('```')) {
    return true;
  }
  final header = RegExp(r'(^|\n)#{1,6}\s');
  if (header.hasMatch(text)) {
    return true;
  }
  final list = RegExp(r'(^|\n)\s*([-*+]\s|\d+\.\s|\-\s\[[ xX]\]\s)');
  if (list.hasMatch(text)) {
    return true;
  }
  final quote = RegExp(r'(^|\n)>\s');
  if (quote.hasMatch(text)) {
    return true;
  }
  final link = RegExp(r'\[[^\]]+\]\([^)]+\)');
  if (link.hasMatch(text)) {
    return true;
  }
  final table = RegExp(r'(^|\n)\|.+\|\n\|[-:\s|]+\|');
  if (table.hasMatch(text)) {
    return true;
  }
  final inlineCode = RegExp(r'`[^`]+`');
  if (inlineCode.hasMatch(text)) {
    return true;
  }
  final bold = RegExp(r'\*\*[^*]+\*\*');
  if (bold.hasMatch(text)) {
    return true;
  }
  return false;
}
