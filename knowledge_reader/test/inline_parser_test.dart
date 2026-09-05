import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_reader/domain/rule/inline_parser.dart';

void main() {
  final specFile = File('test/fixtures/inline/inline-spec.json');
  final spec = jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
  final cases = (spec['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  test('inline spec declares version 1', () {
    expect(spec['specVersion'], 1);
  });

  for (final inlineCase in cases) {
    test('inline case: ${inlineCase['name']}', () {
      final tokens = parseInlineText(inlineCase['input'] as String);
      expect(_encode(tokens), inlineCase['tokens']);
    });
  }

  test('parser never throws on malformed input', () {
    for (final input in ['**unclosed', '`code', '[link](', r'\', '![img](']) {
      expect(() => parseInlineText(input), returnsNormally);
    }
  });
}

List<Map<String, dynamic>> _encode(List<InlineToken> tokens) =>
    tokens.map(_encodeToken).toList(growable: false);

Map<String, dynamic> _encodeToken(InlineToken token) {
  switch (token) {
    case TextToken(:final value):
      return {'type': 'text', 'value': value};
    case CodeToken(:final value):
      return {'type': 'code', 'value': value};
    case MathToken(:final value):
      return {'type': 'math', 'value': value};
    case SoftBreakToken():
      return {'type': 'soft_break'};
    case StrongToken(:final children):
      return {'type': 'strong', 'children': _encode(children)};
    case EmphasisToken(:final children):
      return {'type': 'em', 'children': _encode(children)};
    case StrikethroughToken(:final children):
      return {'type': 'del', 'children': _encode(children)};
    case LinkToken(:final href, :final children):
      return {'type': 'link', 'href': href, 'children': _encode(children)};
    case InlineImageToken(:final src, :final alt):
      return {'type': 'inline_image', 'src': src, 'alt': alt};
  }
}
