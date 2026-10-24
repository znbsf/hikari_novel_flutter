import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/pages/reader/controller.dart';

void main() {
  const catalogue = <List<String>>[
    ['101', '102', '103'],
    ['201', '202'],
  ];

  test('找到第一卷章节', () {
    expect(findIndexPositionInCatalogue({'catalogue': catalogue, 'cid': '102'}), [0, 1]);
  });

  test('找到第二卷章节', () {
    expect(findIndexPositionInCatalogue({'catalogue': catalogue, 'cid': '202'}), [1, 1]);
  });

  test('找不到章节', () {
    expect(findIndexPositionInCatalogue({'catalogue': catalogue, 'cid': '999'}), null);
  });

  test('空目录', () {
    expect(findIndexPositionInCatalogue({'catalogue': <List<String>>[], 'cid': '101'}), null);
  });

  test('跳过空卷，重复章节返回第一次出现的位置', () {
    expect(
      findIndexPositionInCatalogue({
        'catalogue': <List<String>>[
          [],
          ['101'],
          ['101'],
        ],
        'cid': '101',
      }),
      [1, 0],
    );
  });
}
