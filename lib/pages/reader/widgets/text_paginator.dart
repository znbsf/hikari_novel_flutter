List<Page> splitText(ComputeParameter parameter) {
  final str = parameter.rawText;
  final img = parameter.rawImage;

  final List<Page> pages = [];

  if (str.isNotEmpty) {
    final reg = RegExp(r"([^\x00-\xff]|\b\w+\b|\p{P}|\x20|\S|\u3000|\n)");
    final chineseExp = RegExp(r"[^\x00-\xff]");
    final wordExp = RegExp(r"\w+");
    final symbolExp = RegExp(r"\p{P}");
    final newLineExp = RegExp(r"\n");

    final paragraphs = str.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n+')).where((e) => e.trim().isNotEmpty).toList();
    final indentPrefix = parameter.paraIndent > 0 ? List.filled(parameter.paraIndent, '　').join() : '';
    final List<TextRow> allRows = [];

    void flushWrappedLine(String line, {required bool paragraphEnd, required bool isFirstLineOfParagraph}) {
      final source = isFirstLineOfParagraph ? '$indentPrefix${line.trimLeft()}' : line;
      if (source.isEmpty) {
        allRows.add(TextRow('', paragraphEnd: paragraphEnd));
        return;
      }

      final lineMatches = reg.allMatches(source).map((match) => match.group(0) ?? '').toList();
      String rowText = '';
      double currentRowWidth = 0;

      for (final item in lineMatches) {
        final charInfo = charsFromToken(item, parameter, chineseExp, wordExp, symbolExp, newLineExp);
        if ((currentRowWidth + charInfo.width) > parameter.width && rowText.isNotEmpty) {
          allRows.add(TextRow(rowText, paragraphEnd: false));
          rowText = '';
          currentRowWidth = 0;
        }
        rowText += charInfo.text;
        currentRowWidth += charInfo.width;
      }

      allRows.add(TextRow(rowText, paragraphEnd: paragraphEnd));
    }

    for (final paragraph in paragraphs) {
      final lines = paragraph.split('\n');
      for (int i = 0; i < lines.length; i++) {
        flushWrappedLine(lines[i], paragraphEnd: i == lines.length - 1, isFirstLineOfParagraph: i == 0);
      }
    }

    List<TextRow> currentTextPage = [];
    double currentPageHeight = 0;
    final pageLimit = parameter.pageHeight > 0 ? parameter.pageHeight : (parameter.maxLine * parameter.fontHeight);

    for (final row in allRows) {
      final rowHeight = parameter.fontHeight + (row.paragraphEnd ? parameter.paraSpacing : 0);
      if (currentTextPage.isNotEmpty && (currentPageHeight + rowHeight) > pageLimit) {
        pages.add(TextPage(pages.length, currentTextPage));
        currentTextPage = [];
        currentPageHeight = 0;
      }
      currentTextPage.add(row);
      currentPageHeight += rowHeight;
    }

    if (currentTextPage.isNotEmpty) {
      pages.add(TextPage(pages.length, currentTextPage));
    }

    if (pages.length == 1) {
      final first = pages.first as TextPage;
      if (first.rows.length == 1 && first.rows.first.text.isEmpty) {
        return [];
      }
    }
  }

  if (img.isNotEmpty) {
    for (final i in img) {
      pages.add(ImagePage(pages.length, i));
    }
  }

  return pages;
}

CharInfo charsFromToken(String item, ComputeParameter parameter, RegExp chineseExp, RegExp wordExp, RegExp symbolExp, RegExp newLineExp) {
  if (chineseExp.hasMatch(item)) {
    return CharInfo(text: item, width: parameter.chineseWidth, type: CharType.chinese);
  }
  if (wordExp.hasMatch(item)) {
    return CharInfo(text: item, width: parameter.englishWidth * item.length, type: CharType.word);
  }
  if (newLineExp.hasMatch(item)) {
    return CharInfo(text: '', width: 0, type: CharType.newline);
  }
  if (item == ' ') {
    return CharInfo(text: item, width: parameter.spaceWidth, type: CharType.symbol);
  }
  if (symbolExp.hasMatch(item)) {
    return CharInfo(text: item, width: parameter.symbolWidth, type: CharType.symbol);
  }
  return CharInfo(text: item, width: parameter.symbolWidth, type: CharType.symbol);
}

enum CharType {
  //中文及全角符号
  chinese,
  //单词
  word,
  //数字
  number,
  //符号
  symbol,
  //换行符
  newline,
}

class CharInfo {
  CharType type;
  String text;
  double width;

  CharInfo({required this.text, required this.width, required this.type});

  @override
  String toString() {
    return "($type,$width,$text)";
  }
}

class ComputeParameter {
  String rawText;
  List<String> rawImage;
  double width;
  double fontSize;
  double lineHeight;
  double pageHeight;
  double paraSpacing;
  int paraIndent;
  int maxLine;
  double chineseWidth;
  double englishWidth;
  double symbolWidth;
  double spaceWidth;
  double fontHeight;

  ComputeParameter({
    required this.rawText,
    required this.rawImage,
    required this.fontSize,
    required this.width,
    required this.maxLine,
    required this.pageHeight,
    required this.lineHeight,
    required this.paraSpacing,
    required this.paraIndent,
    required this.chineseWidth,
    required this.englishWidth,
    required this.symbolWidth,
    required this.spaceWidth,
    required this.fontHeight,
  });
}

abstract class Page {
  final int index;

  Page(this.index);
}

class TextPage extends Page {
  final List<TextRow> rows;

  TextPage(super.index, this.rows);
}

class TextRow {
  final String text;
  final bool paragraphEnd;

  const TextRow(this.text, {this.paragraphEnd = false});
}

class ImagePage extends Page {
  final String url;

  ImagePage(super.index, this.url);
}
