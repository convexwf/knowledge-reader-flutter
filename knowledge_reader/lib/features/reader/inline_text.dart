import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/rule/inline_parser.dart';

/// Resolves an `assets/<assetId>` reference to a local file path, if installed.
typedef AssetPathResolver = String? Function(String assetId);

/// Renders inline text using the token stream from the inline parser.
class InlineText extends StatefulWidget {
  const InlineText({
    super.key,
    required this.text,
    required this.style,
    this.onLinkTap,
    this.assetPathResolver,
    this.maxImageHeight = 320,
  });

  final String text;
  final TextStyle style;
  final void Function(String href)? onLinkTap;
  final AssetPathResolver? assetPathResolver;
  final double maxImageHeight;

  @override
  State<InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<InlineText> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineToken> _tokens = const [];

  @override
  void initState() {
    super.initState();
    _tokens = parseInlineText(widget.text);
  }

  @override
  void didUpdateWidget(covariant InlineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _tokens = parseInlineText(widget.text);
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final spans = <InlineSpan>[
      ..._tokens.expand((token) => _spanFor(token, widget.style)),
    ];
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }

  Iterable<InlineSpan> _spanFor(InlineToken token, TextStyle style) {
    switch (token) {
      case TextToken(:final value):
        return [TextSpan(text: value)];
      case SoftBreakToken():
        return const [TextSpan(text: '\n')];
      case CodeToken(:final value):
        return [
          TextSpan(
            text: value,
            style: style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: style.color?.withValues(alpha: 0.08),
            ),
          ),
        ];
      case MathToken(:final value):
        return [
          TextSpan(
            text: value,
            style: style.copyWith(fontFamily: 'monospace', fontStyle: FontStyle.italic),
          ),
        ];
      case StrongToken(:final children):
        return children.expand((child) => _spanFor(child, style.copyWith(fontWeight: FontWeight.w700)));
      case EmphasisToken(:final children):
        return children.expand((child) => _spanFor(child, style.copyWith(fontStyle: FontStyle.italic)));
      case StrikethroughToken(:final children):
        return children.expand((child) => _spanFor(child, style.copyWith(decoration: TextDecoration.lineThrough)));
      case LinkToken(:final href, :final children):
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onLinkTap?.call(href);
        _recognizers.add(recognizer);
        return [
          TextSpan(
            children: children.expand((child) => _spanFor(child, linkStyle(style))).toList(growable: false),
            recognizer: recognizer,
          ),
        ];
      case InlineImageToken(:final src, :final alt):
        return [_inlineImage(src, alt)];
    }
  }

  InlineSpan _inlineImage(String src, String alt) {
    final assetId = RegExp(r'(?:^|/)assets/([^/]+)$').firstMatch(src)?.group(1);
    final localPath = assetId == null ? null : widget.assetPathResolver?.call(assetId);
    final image = localPath != null
        ? Image.file(
            File(localPath),
            height: widget.maxImageHeight,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _imagePlaceholder(alt),
          )
        : _imagePlaceholder(alt);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: image,
      ),
    );
  }

  Widget _imagePlaceholder(String alt) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.image_outlined, size: 18, semanticLabel: alt.isEmpty ? '图片' : alt),
      );
}

TextStyle linkStyle(TextStyle style) => style.copyWith(
      color: style.color,
      decoration: TextDecoration.underline,
      decorationColor: style.color?.withValues(alpha: 0.5),
    );
