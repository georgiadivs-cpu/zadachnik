import 'package:flutter/material.dart';

List<TextSpan> buildHighlightSpans({
  required String text,
  required String query,
  TextStyle? style,
  TextStyle? highlightStyle,
}) {
  if (query.isEmpty || text.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }
  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();
  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final index = lowerText.indexOf(lowerQuery, start);
    if (index < 0) {
      if (start < text.length) {
        spans.add(TextSpan(text: text.substring(start), style: style));
      }
      break;
    }
    if (index > start) {
      spans.add(TextSpan(text: text.substring(start, index), style: style));
    }
    spans.add(
      TextSpan(
        text: text.substring(index, index + query.length),
        style: highlightStyle,
      ),
    );
    start = index + query.length;
  }
  return spans.isEmpty ? [TextSpan(text: text, style: style)] : spans;
}

class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: buildHighlightSpans(
          text: text,
          query: query,
          style: style,
          highlightStyle:
              highlightStyle ??
              TextStyle(
                backgroundColor: theme.colorScheme.tertiaryContainer,
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
