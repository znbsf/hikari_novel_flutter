import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/pages/reader/widgets/text_paginator.dart';

const _text =
    '清晨的风吹过山谷，旅人沿着石阶慢慢向前。远处的钟声响起，提醒他新的旅程已经开始。\n'
    '他收起地图，望向云层之间露出的蓝天。\n\n'
    '午后的街道渐渐热闹起来，书店门前有人停下脚步。她翻开一本旧书，看见夹在书页里的信笺。\n'
    '信上写着 abc 123，还有一行等待重逢的约定。\n\n'
    '夜色降临以后，窗边的灯仍然亮着。故事尚未结束，明天还会有人沿着同一条路走来。';

void main() {
  for (final snapshot in <({double fontSize, int pageCount, List<String> firstStrings})>[
    (fontSize: 16.0, pageCount: 5, firstStrings: ['　　清晨的风吹过山谷，旅', '来，书店门前有人停下脚步', '，明天还会有人沿着同一条', 'image-one.png', 'image-two.png']),
    (fontSize: 20.0, pageCount: 6, firstStrings: ['　　清晨的风吹过山', '层之间露出的蓝天。', '在书页里的信笺。', '窗边的灯仍然亮着。', 'image-one.png', 'image-two.png']),
  ]) {
    test('单页排版快照：字号 ${snapshot.fontSize}', () {
      final fontSize = snapshot.fontSize;
      // 固定字宽和行高，避免系统字体影响分页基线；页面尺寸为 192 × 180。
      final pages = splitText(
        ComputeParameter(
          rawText: _text,
          rawImage: ['image-one.png', 'image-two.png'],
          fontSize: fontSize,
          width: 192,
          maxLine: (180 / (fontSize * 1.5)).floor(),
          pageHeight: 180,
          lineHeight: 1.5,
          paraSpacing: 12,
          paraIndent: 2,
          chineseWidth: fontSize,
          englishWidth: fontSize / 2,
          symbolWidth: fontSize / 2,
          spaceWidth: fontSize / 2,
          fontHeight: fontSize * 1.5,
        ),
      );

      expect(pages, hasLength(snapshot.pageCount));
      expect(pages.map((page) => page.index), List.generate(snapshot.pageCount, (index) => index));
      expect(pages.map((page) => page is TextPage ? page.rows.first.text : (page as ImagePage).url), snapshot.firstStrings);
      expect(pages.take(snapshot.pageCount - 2), everyElement(isA<TextPage>()));
      expect(pages.skip(snapshot.pageCount - 2), everyElement(isA<ImagePage>()));
    });
  }
}
