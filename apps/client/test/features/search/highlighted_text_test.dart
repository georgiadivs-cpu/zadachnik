import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/features/search/presentation/highlighted_text.dart';

void main() {
  test('подсвечивает все совпадения без учёта регистра', () {
    const highlight = TextStyle(backgroundColor: Colors.yellow);
    final spans = buildHighlightSpans(
      text: 'План и план',
      query: 'ПЛАН',
      highlightStyle: highlight,
    );

    expect(spans, hasLength(3));
    expect(spans[0].text, 'План');
    expect(spans[0].style, highlight);
    expect(spans[1].text, ' и ');
    expect(spans[1].style, isNull);
    expect(spans[2].text, 'план');
    expect(spans[2].style, highlight);
  });

  test('возвращает исходный текст без запроса', () {
    final spans = buildHighlightSpans(text: 'Текст', query: '');
    expect(spans, hasLength(1));
    expect(spans.single.text, 'Текст');
  });

  test('возвращает исходный текст без совпадений', () {
    final spans = buildHighlightSpans(text: 'Текст', query: 'план');
    expect(spans, hasLength(1));
    expect(spans.single.text, 'Текст');
  });

  testWidgets('HighlightedText отображается', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HighlightedText(text: 'Планы на неделю', query: 'план'),
        ),
      ),
    );

    expect(find.textContaining('Планы', findRichText: true), findsOneWidget);
  });
}
