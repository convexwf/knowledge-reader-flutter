import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../application/providers.dart';
import '../../data/local/library_store.dart';
import '../../domain/model/document.dart';
import '../../domain/rule/heading_tree.dart';
import 'inline_text.dart';
import 'section_widgets.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _itemScrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openItem());
    _positionsListener.itemPositions.addListener(_scheduleProgressSave);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _positionsListener.itemPositions.removeListener(_scheduleProgressSave);
    super.dispose();
  }

  Future<void> _openItem() async {
    final catalog = ref.read(catalogProvider).value;
    final item = catalog?.snapshot.items
        .where((entry) => entry.itemId == widget.itemId)
        .firstOrNull;
    if (item == null) return;
    await ref.read(readerProvider.notifier).open(item);
  }

  void _scheduleProgressSave() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(seconds: 2), _saveProgress);
  }

  Future<void> _saveProgress() async {
    final state = ref.read(readerProvider).value;
    final document = state?.document;
    if (document == null) return;
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions.reduce((a, b) => a.index <= b.index ? a : b);
    final sectionIndex = first.index - 1;
    if (sectionIndex < 0 || sectionIndex >= document.sections.length) return;
    final section = document.sections[sectionIndex];
    final sectionId = section.sectionId ?? section.anchorId ?? 'index-$sectionIndex';
    await ref.read(readerProvider.notifier).saveProgress(
          sectionId,
          first.itemLeadingEdge.clamp(0, 1),
          sectionIndex: sectionIndex,
          sectionCount: document.sections.length,
        );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(preferencesProvider).value ?? const ReaderPreferences();
    final state = ref.watch(readerProvider);
    final readerState = state.value;
    final theme = preferences.theme;
    final baseStyle = TextStyle(
      color: theme.foreground,
      fontSize: 16 * preferences.fontScale,
      height: preferences.lineHeight,
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(
          readerState?.item.title ?? '阅读',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '字号',
            icon: const Icon(Icons.format_size),
            onPressed: () => _showFontSheet(context),
          ),
          IconButton(
            tooltip: '主题',
            icon: const Icon(Icons.contrast),
            onPressed: () => _cycleTheme(preferences),
          ),
          if (readerState?.document != null)
            IconButton(
              tooltip: '目录',
              icon: const Icon(Icons.list_alt),
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
        ],
      ),
      endDrawer: readerState?.document == null
          ? null
          : _OutlineDrawer(
              document: readerState!.document!,
              onSelect: (index) {
                Navigator.of(context).pop();
                _itemScrollController.scrollTo(index: index + 1, duration: const Duration(milliseconds: 260));
              },
            ),
      body: switch (state) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => _message('加载失败：$error'),
        _ when readerState?.document == null => _message(readerState?.warning ?? '没有可显示的内容'),
        _ => _document(readerState!, baseStyle, preferences),
      },
    );
  }

  Widget _document(ReaderState state, TextStyle baseStyle, ReaderPreferences preferences) {
    final document = state.document!;
    final resolver = _assetResolver(state);
    final restoreIndex = _restoreIndex(document, state.progress);

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _positionsListener,
      initialScrollIndex: restoreIndex,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      itemCount: document.sections.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _header(document, baseStyle, state);
        return SectionView(
          section: document.sections[index - 1],
          baseStyle: baseStyle,
          headingIndex: index,
          onLinkTap: _openLink,
          assetPathResolver: resolver,
        );
      },
    );
  }

  int _restoreIndex(KnowledgeDocument document, ReadingProgress? progress) {
    final sectionId = progress?.sectionId;
    if (sectionId == null) return 0;
    final index = document.sections.indexWhere(
      (section) => section.sectionId == sectionId || section.anchorId == sectionId,
    );
    return index < 0 ? 0 : index + 1;
  }

  AssetPathResolver _assetResolver(ReaderState state) {
    final itemId = state.item.itemId;
    final library = ref.read(libraryIndexProvider).value ?? const {};
    final local = library[itemId];
    if (local == null) return (_) => null;
    return (assetId) {
      final store = ref.read(libraryStoreProvider).value;
      if (store == null) return null;
      final file = store.assetFile(itemId, local.contentHash, assetId);
      return file.path;
    };
  }

  Widget _header(KnowledgeDocument document, TextStyle baseStyle, ReaderState state) {
    final meta = document.meta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meta.title,
          style: baseStyle.copyWith(fontSize: baseStyle.fontSize! * 1.7, fontWeight: FontWeight.w700, height: 1.25),
        ),
        if (meta.authors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(meta.authors.join('、'), style: baseStyle.copyWith(color: baseStyle.color!.withValues(alpha: 0.7))),
          ),
        if (meta.sourceUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              meta.sourceUrl!,
              style: baseStyle.copyWith(fontSize: 12, color: baseStyle.color!.withValues(alpha: 0.6)),
            ),
          ),
        if (!state.offline)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('仅在线（未下载离线包）', style: baseStyle.copyWith(fontSize: 12, color: Colors.orange)),
          ),
        const Divider(height: 28),
      ],
    );
  }

  Future<void> _openLink(String href) async {
    if (href.startsWith('#')) {
      final document = ref.read(readerProvider).value?.document;
      if (document == null) return;
      final target = document.sections.indexWhere(
        (section) => section.anchorId == href.substring(1) || section.sectionId == href.substring(1),
      );
      if (target >= 0) {
        _itemScrollController.scrollTo(index: target + 1, duration: const Duration(milliseconds: 260));
      }
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https' || scheme == 'mailto') {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  void _cycleTheme(ReaderPreferences preferences) {
    final next = ReaderTheme.values[(preferences.theme.index + 1) % ReaderTheme.values.length];
    ref.read(preferencesProvider.notifier).save(preferences.copyWith(theme: next));
  }

  void _showFontSheet(BuildContext context) {
    final preferences = ref.read(preferencesProvider).value ?? const ReaderPreferences();
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('字号与行距'),
              Row(
                children: [
                  const Text('字号'),
                  Expanded(
                    child: Slider(
                      value: preferences.fontScale,
                      min: 0.8,
                      max: 1.6,
                      divisions: 16,
                      label: preferences.fontScale.toStringAsFixed(1),
                      onChanged: (value) {
                        final next = preferences.copyWith(fontScale: value);
                        ref.read(preferencesProvider.notifier).save(next);
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('行距'),
                  Expanded(
                    child: Slider(
                      value: preferences.lineHeight,
                      min: 1.2,
                      max: 2.2,
                      divisions: 10,
                      label: preferences.lineHeight.toStringAsFixed(1),
                      onChanged: (value) {
                        final next = preferences.copyWith(lineHeight: value);
                        ref.read(preferencesProvider.notifier).save(next);
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineDrawer extends StatelessWidget {
  const _OutlineDrawer({required this.document, required this.onSelect});

  final KnowledgeDocument document;
  final void Function(int sectionIndex) onSelect;

  @override
  Widget build(BuildContext context) {
    final tree = buildHeadingTree(document.sections);
    return Drawer(
      child: SafeArea(
        child: tree.isEmpty
            ? const Center(child: Text('本文档没有标题'))
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: _nodes(tree, 0),
              ),
      ),
    );
  }

  List<Widget> _nodes(List<HeadingNode> nodes, int depth) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      widgets.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 16 + depth * 14.0, right: 12),
          title: Text(node.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => onSelect(node.sectionIndex),
        ),
      );
      if (node.children.isNotEmpty) {
        widgets.addAll(_nodes(node.children, depth + 1));
      }
    }
    return widgets;
  }
}
