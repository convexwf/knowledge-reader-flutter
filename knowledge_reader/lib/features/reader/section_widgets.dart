import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/model/document.dart';
import '../../domain/rule/heading_tree.dart';
import 'inline_text.dart';

/// Renders one document section as a native widget.
class SectionView extends StatelessWidget {
  const SectionView({
    super.key,
    required this.section,
    required this.baseStyle,
    required this.headingIndex,
    this.onLinkTap,
    this.assetPathResolver,
  });

  final DocumentSection section;
  final TextStyle baseStyle;
  final int headingIndex;
  final void Function(String href)? onLinkTap;
  final AssetPathResolver? assetPathResolver;

  @override
  Widget build(BuildContext context) {
    switch (section.type) {
      case SectionType.heading:
        return _heading();
      case SectionType.blockquote:
        return _blockquote();
      case SectionType.list:
        return _list(context);
      case SectionType.table:
        return _table(context);
      case SectionType.code:
        return _code(context);
      case SectionType.figure:
        return _figure(context);
      default:
        return _paragraph();
    }
  }

  Widget _paragraph() {
    final content = section.content ?? '';
    if (content.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InlineText(
        text: content,
        style: baseStyle,
        onLinkTap: onLinkTap,
        assetPathResolver: assetPathResolver,
      ),
    );
  }

  Widget _heading() {
    final level = (section.level ?? 2).clamp(1, 6);
    final scale = switch (level) {
      1 => 1.7,
      2 => 1.42,
      3 => 1.24,
      4 => 1.12,
      5 => 1.04,
      _ => 1.0,
    };
    final style = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 16) * scale,
      fontWeight: level <= 2 ? FontWeight.w700 : FontWeight.w600,
      height: 1.3,
    );
    return Padding(
      padding: EdgeInsets.only(top: level <= 2 ? 22 : 16, bottom: 6),
      child: InlineText(
        text: section.content ?? '',
        style: style,
        onLinkTap: onLinkTap,
        assetPathResolver: assetPathResolver,
      ),
    );
  }

  Widget _blockquote() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: baseStyle.color!.withValues(alpha: 0.35), width: 3),
        ),
      ),
      child: InlineText(
        text: section.content ?? '',
        style: baseStyle.copyWith(fontStyle: FontStyle.italic, color: baseStyle.color?.withValues(alpha: 0.85)),
        onLinkTap: onLinkTap,
        assetPathResolver: assetPathResolver,
      ),
    );
  }

  Widget _list(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _listItems(section.items, 0),
      ),
    );
  }

  List<Widget> _listItems(List<SectionListItem> items, int depth) {
    final indent = depth.clamp(0, 5) * 18.0;
    return items.map((item) {
      return Padding(
        padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 1),
              child: Text(depth == 0 ? '•' : '◦', style: baseStyle),
            ),
            Expanded(child: _listItemText(item)),
          ],
        ),
      );
    }).toList(growable: false);
  }

  Widget _listItemText(SectionListItem item) {
    final children = <Widget>[
      InlineText(
        text: item.text,
        style: baseStyle,
        onLinkTap: onLinkTap,
        assetPathResolver: assetPathResolver,
      ),
    ];
    if (item.children.isNotEmpty) {
      children.addAll(_listItems(item.children, _childDepth(item)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  int _childDepth(SectionListItem item) => item.children.isEmpty ? 0 : 1;

  Widget _table(BuildContext context) {
    final rows = section.rows;
    if (rows.isEmpty) return _paragraph();
    final divider = TableBorder.all(color: baseStyle.color!.withValues(alpha: 0.18), width: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 48),
          child: Table(
            border: divider,
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1)
                TableRow(
                  decoration: rowIndex == 0
                      ? BoxDecoration(color: baseStyle.color!.withValues(alpha: 0.05))
                      : null,
                  children: [
                    for (final cell in rows[rowIndex])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: InlineText(
                          text: cell,
                          style: baseStyle.copyWith(
                            fontWeight: rowIndex == 0 ? FontWeight.w600 : FontWeight.w400,
                          ),
                          onLinkTap: onLinkTap,
                          assetPathResolver: assetPathResolver,
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

  Widget _code(BuildContext context) {
    final language = section.language;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: baseStyle.color!.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (language != null && language.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Text(language, style: baseStyle.copyWith(fontSize: 11, color: baseStyle.color!.withValues(alpha: 0.6))),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                section.content ?? '',
                style: baseStyle.copyWith(fontFamily: 'monospace', fontSize: (baseStyle.fontSize ?? 16) * 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _figure(BuildContext context) {
    final assets = section.assets;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final asset in assets) _figureImage(context, asset),
          if (section.content != null && section.content!.trim().isNotEmpty) _paragraph(),
        ],
      ),
    );
  }

  Widget _figureImage(BuildContext context, SectionAsset asset) {
    final assetId = asset.resolvedAssetId;
    final localPath = assetId == null ? null : assetPathResolver?.call(assetId);
    final caption = asset.caption ?? asset.alt ?? '';
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (localPath != null)
          Image.file(
            File(localPath),
            width: width,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _missingImage(caption),
          )
        else
          _missingImage(caption),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: InlineText(
              text: caption,
              style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 16) * 0.86, color: baseStyle.color!.withValues(alpha: 0.7)),
              assetPathResolver: assetPathResolver,
              onLinkTap: onLinkTap,
            ),
          ),
      ],
    );
  }

  Widget _missingImage(String caption) => Container(
        height: 120,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: baseStyle.color!.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          caption.isEmpty ? '图片未离线' : caption,
          style: baseStyle.copyWith(color: baseStyle.color!.withValues(alpha: 0.6)),
          textAlign: TextAlign.center,
        ),
      );
}

/// Heading label helper shared with the outline drawer.
String headingLabel(DocumentSection section) => section.content ?? '';

/// Anchor used for outline jumping.
String anchorForSection(DocumentSection section, int headingIndex) =>
    section.anchorId ?? slugifyHeading(headingLabel(section), headingIndex);
