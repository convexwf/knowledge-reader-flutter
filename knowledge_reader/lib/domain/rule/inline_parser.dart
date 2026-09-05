/// Inline text parser implementing the contract in `doc/rendering-layer.md`.
///
/// Grammar (normalized form): `**strong**`, `_emphasis_`, `` `code` ``,
/// `[label](href)`, `$math$`, soft line breaks, plus the lenient aliases
/// `*em*`, `__strong__`, `***strong em***`, `~~strike~~`, `![alt](src)`
/// and bare `http(s)` autolinks.
library;

sealed class InlineToken {
  const InlineToken();
}

class TextToken extends InlineToken {
  const TextToken(this.value);
  final String value;
}

class CodeToken extends InlineToken {
  const CodeToken(this.value);
  final String value;
}

class MathToken extends InlineToken {
  const MathToken(this.value);
  final String value;
}

class SoftBreakToken extends InlineToken {
  const SoftBreakToken();
}

class StrongToken extends InlineToken {
  const StrongToken(this.children);
  final List<InlineToken> children;
}

class EmphasisToken extends InlineToken {
  const EmphasisToken(this.children);
  final List<InlineToken> children;
}

class StrikethroughToken extends InlineToken {
  const StrikethroughToken(this.children);
  final List<InlineToken> children;
}

class LinkToken extends InlineToken {
  const LinkToken({required this.href, required this.children});
  final String href;
  final List<InlineToken> children;
}

class InlineImageToken extends InlineToken {
  const InlineImageToken({required this.src, required this.alt});
  final String src;
  final String alt;
}

const _escapableCharacters = r'\`*_{}[]()#+-.!|~<>$';
const _maxEmphasisDepth = 2;
const _autolinkPattern = r'https?://[^\s<>"' "'" r']+';
/// Punctuation that never belongs to a URL, including CJK sentence marks.
const _trailingUrlPunctuation = '.,;:!?)]}\u3002\uff0c\u3001\uff1b\uff1a\uff01\uff1f\uff09\u3011\u300b\u300d\u300f\u201d\u2019';

/// Parses inline text into a token stream. Never throws; unknown syntax is
/// returned as plain text so a malformed section cannot break the reader.
List<InlineToken> parseInlineText(String text) {
  if (text.isEmpty) return const [];
  try {
    return _mergeTextTokens(_parseStructural(text));
  } catch (_) {
    return [TextToken(text)];
  }
}

/// Merges neighbouring text tokens so escaping can emit literal segments
/// without changing the observable token stream.
List<InlineToken> _mergeTextTokens(List<InlineToken> tokens) {
  final merged = <InlineToken>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    merged.add(TextToken(buffer.toString()));
    buffer.clear();
  }

  for (final token in tokens) {
    if (token is TextToken) {
      buffer.write(token.value);
      continue;
    }
    flush();
    merged.add(token);
  }
  flush();
  return merged;
}

List<InlineToken> _parseStructural(String text) {
  final tokens = <InlineToken>[];
  final buffer = StringBuffer();
  var index = 0;

  void flush() {
    if (buffer.isEmpty) return;
    tokens.add(TextToken(buffer.toString()));
    buffer.clear();
  }

  while (index < text.length) {
    final char = text[index];

    if (char == r'\' && index + 1 < text.length && _escapableCharacters.contains(text[index + 1])) {
      // Escapes are authoritative: emit the literal character immediately so it
      // can never be reinterpreted as an emphasis marker.
      flush();
      tokens.add(TextToken(text[index + 1]));
      index += 2;
      continue;
    }

    if (char == '`') {
      final end = text.indexOf('`', index + 1);
      if (end > index) {
        flush();
        tokens.add(CodeToken(text.substring(index + 1, end)));
        index = end + 1;
        continue;
      }
    }

    if (char == '!' && index + 1 < text.length && text[index + 1] == '[') {
      final image = _tryParseLink(text, index + 1);
      if (image != null) {
        flush();
        tokens.add(InlineImageToken(src: image.href, alt: image.label));
        index = image.end;
        continue;
      }
    }

    if (char == '[') {
      final link = _tryParseLink(text, index);
      if (link != null) {
        flush();
        tokens.add(LinkToken(href: link.href, children: _parseEmphasis(link.label, 0)));
        index = link.end;
        continue;
      }
    }

    if (char == r'$') {
      final end = text.indexOf(r'$', index + 1);
      final newline = text.indexOf('\n', index + 1);
      if (end > index && (newline == -1 || end < newline)) {
        flush();
        tokens.add(MathToken(text.substring(index + 1, end)));
        index = end + 1;
        continue;
      }
    }

    if (char == '\n') {
      flush();
      tokens.add(const SoftBreakToken());
      index += 1;
      continue;
    }

    buffer.write(char);
    index += 1;
  }

  flush();
  return _applyTextRules(tokens);
}

class _ParsedLink {
  const _ParsedLink({required this.label, required this.href, required this.end});
  final String label;
  final String href;
  final int end;
}

_ParsedLink? _tryParseLink(String text, int start) {
  if (start >= text.length || text[start] != '[') return null;
  final labelEnd = text.indexOf('](', start + 1);
  if (labelEnd == -1) return null;
  final hrefEnd = text.indexOf(')', labelEnd + 2);
  if (hrefEnd == -1) return null;
  final label = text.substring(start + 1, labelEnd);
  final href = text.substring(labelEnd + 2, hrefEnd).trim();
  if (label.isEmpty || href.isEmpty || !_isSafeLink(href)) return null;
  return _ParsedLink(label: label, href: href, end: hrefEnd + 1);
}

bool _isSafeLink(String href) {
  if (href.startsWith('#')) return true;
  final lowered = href.toLowerCase();
  return lowered.startsWith('http://') || lowered.startsWith('https://') || lowered.startsWith('mailto:');
}

/// Applies autolink splitting and emphasis matching to plain text tokens.
List<InlineToken> _applyTextRules(List<InlineToken> tokens) {
  final result = <InlineToken>[];
  for (final token in tokens) {
    if (token is TextToken) {
      result.addAll(_applyAutolinks(token.value));
    } else {
      result.add(token);
    }
  }
  return result;
}

List<InlineToken> _applyAutolinks(String text) {
  final pattern = RegExp(_autolinkPattern);
  final result = <InlineToken>[];
  var lastIndex = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > lastIndex) {
      result.addAll(_parseEmphasis(text.substring(lastIndex, match.start), 0));
    }
    var url = match.group(0)!;
    while (url.isNotEmpty && _trailingUrlPunctuation.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    result.add(LinkToken(href: url, children: [TextToken(url)]));
    lastIndex = match.start + url.length;
  }
  if (lastIndex < text.length) {
    result.addAll(_parseEmphasis(text.substring(lastIndex), 0));
  }
  return result;
}

final _emphasisPatterns = <({RegExp pattern, String kind})>[
  (pattern: RegExp(r'\*\*\*(.+?)\*\*\*'), kind: 'strongEm'),
  (pattern: RegExp(r'___(.+?)___'), kind: 'strongEm'),
  (pattern: RegExp(r'\*\*(.+?)\*\*'), kind: 'strong'),
  (pattern: RegExp(r'__(.+?)__'), kind: 'strong'),
  (pattern: RegExp(r'\*(.+?)\*'), kind: 'em'),
  (pattern: RegExp(r'_(.+?)_'), kind: 'em'),
  (pattern: RegExp(r'~~(.+?)~~'), kind: 'strike'),
];

List<InlineToken> _parseEmphasis(String text, int depth) {
  if (text.isEmpty) return const [];
  if (depth >= _maxEmphasisDepth) return [TextToken(text)];

  for (final rule in _emphasisPatterns) {
    final match = rule.pattern.firstMatch(text);
    if (match == null) continue;
    final inner = match.group(1) ?? '';
    final children = _parseEmphasis(inner, depth + 1);
    final before = text.substring(0, match.start);
    final after = text.substring(match.end);
    return [
      ..._parseEmphasis(before, depth),
      switch (rule.kind) {
        'strongEm' => StrongToken([EmphasisToken(children)]),
        'strong' => StrongToken(children),
        'strike' => StrikethroughToken(children),
        _ => EmphasisToken(children),
      },
      ..._parseEmphasis(after, depth),
    ];
  }

  return [TextToken(_unescape(text))];
}

String _unescape(String text) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char == r'\' && index + 1 < text.length && _escapableCharacters.contains(text[index + 1])) {
      buffer.write(text[index + 1]);
      index += 2;
      continue;
    }
    buffer.write(char);
    index += 1;
  }
  return buffer.toString();
}
