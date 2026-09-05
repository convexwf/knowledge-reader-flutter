import '../model/document.dart';

/// Heading entry in the reader outline.
class HeadingNode {
  HeadingNode({
    required this.level,
    required this.title,
    required this.sectionIndex,
    required this.anchorId,
  });

  final int level;
  final String title;
  final int sectionIndex;
  final String anchorId;
  final List<HeadingNode> children = [];
}

/// Stable anchor for a heading, matching the web reader implementation.
String slugifyHeading(String text, int index) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
  return normalized.isEmpty ? 'section-$index' : '$normalized-$index';
}

/// Builds the nested outline using the same stack algorithm as the web reader.
List<HeadingNode> buildHeadingTree(List<DocumentSection> sections) {
  final roots = <HeadingNode>[];
  final stack = <HeadingNode>[];
  var headingIndex = 1;

  for (var index = 0; index < sections.length; index += 1) {
    final section = sections[index];
    if (section.type != SectionType.heading) continue;
    final title = section.content ?? '';
    if (title.trim().isEmpty) continue;
    final level = (section.level ?? 2).clamp(1, 6);
    final node = HeadingNode(
      level: level,
      title: title,
      sectionIndex: index,
      anchorId: section.anchorId ?? slugifyHeading(title, headingIndex),
    );
    headingIndex += 1;

    while (stack.isNotEmpty && stack.last.level >= node.level) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.children.add(node);
    }
    stack.add(node);
  }

  return roots;
}
