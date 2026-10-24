import 'package:easy_refresh/easy_refresh.dart';
import 'package:get/get.dart' show Get, GetNavigation;
import '../../../models/reader_direction.dart';
import '../../../router/route_path.dart';
import '../controller.dart';
import 'custom_header.dart';
import 'refresh_indicator_box.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Page;

import '../../../common/constants.dart';
import 'paper_curl_pager.dart';
import 'text_paginator.dart';

class HorizontalReadPage extends StatefulWidget {
  final String text;
  final List<String> images;
  final int initIndex;
  final EdgeInsets padding;
  final TextStyle style;
  final PageController controller;
  final bool reverse;
  final bool isDualPage;
  final double dualPageSpacing;
  final bool pageTurningAnimation;
  final int paraSpacing;
  final int paraIndent;
  final PaperCurlPagerController? paperCurlController;
  final Widget? pageFooter;
  final Color? backgroundColor;
  final Color? backsideColor;
  final Function(int index, int max) onPageChanged;
  final Function(int index) onViewImage;
  final VoidCallback? onCenterTap;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final VoidCallback? onReachStart;
  final VoidCallback? onReachEnd;

  const HorizontalReadPage(
    this.text,
    this.images, {
    required this.initIndex,
    required this.padding,
    required this.style,
    required this.controller,
    this.reverse = false,
    required this.isDualPage,
    required this.dualPageSpacing,
    this.pageTurningAnimation = false,
    required this.paraSpacing,
    required this.paraIndent,
    this.paperCurlController,
    this.pageFooter,
    this.backgroundColor,
    this.backsideColor,
    this.onCenterTap,
    this.onLeftTap,
    this.onRightTap,
    this.onReachStart,
    this.onReachEnd,
    required this.onPageChanged,
    required this.onViewImage,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _HorizontalReadPageState();
}

class _HorizontalReadPageState extends State<HorizontalReadPage> with WidgetsBindingObserver {
  List<Page> pages = [];
  String text = "";
  List<String> images = [];

  TextStyle textStyle = const TextStyle();
  double fontHeight = 16.0;
  EdgeInsets padding = EdgeInsets.zero;
  late Size lastSize;

  double pageWidth = 0;
  double pageHeight = 0;
  int index = 0; //HorizontalReadPage内部的页面，与PageController的页面无关

  late String _lastLayoutSig;
  int _layoutGeneration = 0;

  int get _safePageCount => _pageCount() <= 0 ? 0 : _pageCount() - 1;

  int _clampPageIndex(int value) => (value.clamp(0, _safePageCount) as num).toInt();

  int _pageCountForLength(int pageLength) {
    if (widget.isDualPage) {
      return (pageLength / 2).ceil();
    }
    return pageLength;
  }

  int _clampPageIndexForCount(int value, int pageCount) {
    if (pageCount <= 0) return 0;
    return (value.clamp(0, pageCount - 1) as num).toInt();
  }

  @override
  void initState() {
    super.initState();
    index = widget.initIndex;
    lastSize = _currentViewSize();
    _lastLayoutSig = _layoutSignature();
    WidgetsBinding.instance.addObserver(this);
    resetPage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final newSize = _currentViewSize();
      if (lastSize != newSize) {
        lastSize = newSize;
        final newSig = _layoutSignature();
        if (newSig != _lastLayoutSig) {
          _lastLayoutSig = newSig;
          resetPage();
        }
      }
    });
  }

  void resetPage() {
    final generation = ++_layoutGeneration;
    text = widget.text;
    textStyle = widget.style;
    images = List<String>.from(widget.images); //转换为纯净的List<String>
    padding = widget.padding;
    final size = _currentViewSize();
    pageWidth = (size.width - padding.left - padding.right).floorToDouble();
    pageWidth = widget.isDualPage ? (pageWidth - widget.dualPageSpacing * 2) / 2 : pageWidth;
    pageHeight = size.height - padding.top - padding.bottom;
    if (text.isEmpty && images.isEmpty) {
      index = 0;
      setState(() {
        pages = [];
      });
      return;
    }
    initPage(generation, index);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutGeneration) return;
      widget.onPageChanged(index, _pageCount()); //页面加载完成时，提醒保存进度
    });
  }

  @override
  void didUpdateWidget(covariant HorizontalReadPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final contentChanged = widget.text != oldWidget.text || !listEquals(widget.images, oldWidget.images);
    final newSig = _layoutSignature();
    if (contentChanged) {
      _lastLayoutSig = newSig;
      index = widget.initIndex;
      setState(() {
        pages = [];
      });
      resetPage();
      return;
    }

    //这里比较排版几何参数（fontSize, textStyle）是否有变化
    //这里不能使用"widget.xxx != oldWidget.xxx"，这是在比较对象，而不是比较其中的参数。比如深浅模式切换导致页面重建，会重建TextStyle对象实例，最终误判
    if (newSig != _lastLayoutSig) {
      _lastLayoutSig = newSig;
      resetPage();
      return;
    }

    if (oldWidget.pageTurningAnimation != widget.pageTurningAnimation || oldWidget.isDualPage != widget.isDualPage) {
      final rawTarget = oldWidget.isDualPage == widget.isDualPage ? index : _convertIndexBetweenPageModes(index, oldWidget.isDualPage, widget.isDualPage);
      final target = _clampPageIndex(rawTarget);
      index = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.pageTurningAnimation) {
          widget.paperCurlController?.jumpToPage(target);
        } else if (widget.controller.hasClients) {
          widget.controller.jumpToPage(target);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageTurningAnimation) {
      final currentIndex = _clampPageIndex(index);
      return PaperCurlPager.builder(
        controller: widget.paperCurlController,
        pageCount: _pageCount(),
        pageBuilder: (_, i) => RepaintBoundary(child: _buildPage(i)),
        initialIndex: currentIndex,
        isPageInteractive: _spreadContainsImage,
        reverse: widget.reverse,
        animationEnabled: true,
        backgroundColor: widget.backgroundColor ?? Theme.of(context).colorScheme.surface,
        backsideColor:
            widget.backsideColor ??
            Color.lerp(
              widget.backgroundColor ?? Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceTint,
              Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
            ),
        onCenterTap: widget.onCenterTap,
        onReachStart: widget.onReachStart,
        onReachEnd: widget.onReachEnd,
        onIndexChanged: (v) {
          index = v;
          widget.onPageChanged(v, _pageCount());
        },
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final width = context.size?.width ?? MediaQuery.of(context).size.width;
        final logicalX = widget.reverse ? (width - details.localPosition.dx).clamp(0.0, width) : details.localPosition.dx;
        final left = width * 0.28;
        final right = width * 0.72;
        if (logicalX <= left) {
          widget.reverse ? widget.onRightTap?.call() : widget.onLeftTap?.call();
          return;
        }
        if (logicalX >= right) {
          widget.reverse ? widget.onLeftTap?.call() : widget.onRightTap?.call();
          return;
        }
        widget.onCenterTap?.call();
      },
      child: PageView.builder(
        controller: widget.controller,
        reverse: widget.reverse,
        itemCount: _pageCount(),
        onPageChanged: (v) {
          index = v;
          widget.onPageChanged(v, _pageCount());
        },
        itemBuilder: (_, i) => _buildPage(i),
      ),
    );
  }

  int _convertIndexBetweenPageModes(int value, bool fromDualPage, bool toDualPage) {
    if (fromDualPage == toDualPage) return value;
    return toDualPage ? value ~/ 2 : value * 2;
  }

  int _pageCount() {
    if (widget.isDualPage) {
      if (pages.length % 2 == 0) {
        return (pages.length / 2).toInt();
      } else {
        return ((pages.length + 1) / 2).toInt();
      }
    } else {
      return pages.length;
    }
  }

  bool _spreadContainsImage(int index) {
    if (!widget.isDualPage) {
      return index >= 0 && index < pages.length && pages[index] is ImagePage;
    }

    final firstIndex = index * 2;
    final secondIndex = firstIndex + 1;
    final firstHasImage = firstIndex >= 0 && firstIndex < pages.length && pages[firstIndex] is ImagePage;
    final secondHasImage = secondIndex >= 0 && secondIndex < pages.length && pages[secondIndex] is ImagePage;
    return firstHasImage || secondHasImage;
  }

  Widget _buildPage(int index) {
    final child = widget.isDualPage ? _buildDualPage(index) : (pages[index] is TextPage ? _buildSingleText(index) : _buildImage(index));

    if (widget.pageFooter == null) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(child: widget.pageFooter!),
        ),
      ],
    );
  }

  Widget _buildDualPage(int i) {
    int firstIndex = i * 2;
    int secondIndex = firstIndex + 1;

    return Padding(
      padding: padding,
      child: SizedBox(
        height: pageHeight,
        child: widget.reverse
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: widget.dualPageSpacing),
                      child: Builder(
                        builder: (_) {
                          if (secondIndex >= pages.length) {
                            return SizedBox.shrink();
                          } else if (pages[secondIndex] is TextPage) {
                            return _buildDualSideText(secondIndex);
                          } else {
                            return _buildImage(secondIndex);
                          }
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: widget.dualPageSpacing), //模拟书脊间隙
                      child: Builder(
                        builder: (_) {
                          if (firstIndex >= pages.length) {
                            return SizedBox.shrink();
                          } else if (pages[firstIndex] is TextPage) {
                            return _buildDualSideText(firstIndex);
                          } else {
                            return _buildImage(firstIndex);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: widget.dualPageSpacing), //模拟书脊间隙
                      child: Builder(
                        builder: (_) {
                          if (firstIndex >= pages.length) {
                            return SizedBox.shrink();
                          } else if (pages[firstIndex] is TextPage) {
                            return _buildDualSideText(firstIndex);
                          } else {
                            return _buildImage(firstIndex);
                          }
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: widget.dualPageSpacing),
                      child: Builder(
                        builder: (_) {
                          if (secondIndex >= pages.length) {
                            return SizedBox.shrink();
                          } else if (pages[secondIndex] is TextPage) {
                            return _buildDualSideText(secondIndex);
                          } else {
                            return _buildImage(secondIndex);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSingleText(int index) {
    return Padding(
      padding: padding,
      child: SizedBox(
        height: pageHeight,
        child: CustomPaint(
          painter: NovelTextPainter(
            (pages[index] as TextPage).rows,
            style: widget.style,
            fontHeight: fontHeight,
            paragraphSpacing: widget.paraSpacing.toDouble(),
          ),
        ),
      ),
    );
  }

  Widget _buildDualSideText(int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: pageHeight,
          width: constraints.maxWidth,
          child: CustomPaint(
            painter: NovelTextPainter(
              (pages[index] as TextPage).rows,
              style: widget.style,
              fontHeight: fontHeight,
              paragraphSpacing: widget.paraSpacing.toDouble(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImage(int imageIndex) {
    return Center(
      child: GestureDetector(
        onDoubleTap: () => widget.onViewImage(imageIndex),
        onLongPress: () => widget.onViewImage(imageIndex),
        child: CachedNetworkImage(
          imageUrl: (pages[imageIndex] as ImagePage).url,
          httpHeaders: kUserAgent,
          fit: BoxFit.contain,
          progressIndicatorBuilder: (context, url, downloadProgress) => Center(child: CircularProgressIndicator(value: downloadProgress.progress)),
          errorWidget: (context, url, error) => Center(child: Column(children: [Icon(Icons.error_outline), Text(error.toString())])),
        ),
      ),
    );
  }

  void initPage(int generation, int targetIndex) async {
    double fontSize = textStyle.fontSize!;
    double lineHeight = textStyle.height!;

    //计算出各类文字的字体大小
    //至于为什么不固定大小是因为主文字大小和行高会变动，需要重新计算
    Size chineseCharSize = calcFontSize("中", fontSize: fontSize, lineHeight: lineHeight);
    fontHeight = chineseCharSize.height; //以中文的高度为准，毕竟是中文阅读器
    Size englishCharSize = calcFontSize("e", fontSize: fontSize, lineHeight: lineHeight);
    Size symbolCharSize = calcFontSize(",", fontSize: fontSize, lineHeight: lineHeight);
    Size spaceCharSize = calcFontSize(" ", fontSize: fontSize, lineHeight: lineHeight);

    //计算一页中的最大行数
    int maxLine = (pageHeight / chineseCharSize.height).floor(); //去小数

    var pages = await compute(
      splitText,
      ComputeParameter(
        rawText: text,
        rawImage: images,
        fontSize: fontSize,
        width: pageWidth,
        maxLine: maxLine,
        pageHeight: pageHeight,
        lineHeight: lineHeight,
        paraSpacing: widget.paraSpacing.toDouble(),
        paraIndent: widget.paraIndent,
        chineseWidth: chineseCharSize.width,
        englishWidth: englishCharSize.width,
        symbolWidth: symbolCharSize.width,
        spaceWidth: spaceCharSize.width,
        fontHeight: fontHeight,
      ),
    );

    if (!mounted || generation != _layoutGeneration) return;

    this.pages = pages;
    index = _clampPageIndexForCount(targetIndex, _pageCountForLength(pages.length));
    widget.onPageChanged(index, _pageCount());

    setState(() {}); //刷新UI

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutGeneration) return;
      if (_pageCount() <= 0) return;
      final target = (index.clamp(0, _pageCount() <= 0 ? 0 : _pageCount() - 1) as num).toInt();
      if (widget.pageTurningAnimation) {
        widget.paperCurlController?.jumpToPage(target);
      } else {
        widget.controller.jumpToPage(target);
      }
    });
  }

  Size calcFontSize(String text, {required double fontSize, required double lineHeight}) {
    TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: lineHeight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    painter.layout(maxWidth: 200);
    return painter.size;
  }

  String _layoutSignature() {
    final s = widget.style;
    final p = widget.padding;
    final size = _currentViewSize();

    return [
      widget.isDualPage,
      widget.dualPageSpacing,
      size.width,
      size.height,
      s.fontSize,
      s.height,
      s.letterSpacing,
      s.wordSpacing,
      s.color?.toARGB32(),
      p.left,
      p.right,
      p.top,
      p.bottom,
      widget.paraIndent,
      widget.paraSpacing,
    ].join("|");
  }

  Size _currentViewSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final view = views.first;
      return view.physicalSize / view.devicePixelRatio;
    }
    return const Size(0, 0);
  }
}

class NovelTextPainter extends CustomPainter {
  final TextStyle style;
  final double fontHeight;
  final double paragraphSpacing;
  final List<TextRow> rows;

  NovelTextPainter(this.rows, {required this.style, required this.fontHeight, required this.paragraphSpacing});

  @override
  void paint(Canvas canvas, Size size) {
    double y = 0;
    for (final row in rows) {
      final textSpan = TextSpan(text: row.text, style: style);
      final textPainter = TextPainter(text: textSpan, maxLines: 1, textAlign: TextAlign.justify, textDirection: TextDirection.ltr);
      textPainter.layout(maxWidth: size.width);
      textPainter.paint(canvas, Offset(0, y));
      y += fontHeight;
      if (row.paragraphEnd) {
        y += paragraphSpacing;
      }
    }
  }

  @override
  bool shouldRepaint(covariant NovelTextPainter oldDelegate) {
    return oldDelegate.style != style || oldDelegate.rows != rows || oldDelegate.fontHeight != fontHeight || oldDelegate.paragraphSpacing != paragraphSpacing;
  }
}

class HorizontalReader extends StatelessWidget {
  const HorizontalReader({super.key, required this.controller, required this.padding, required this.style, this.footer});

  final ReaderController controller;
  final EdgeInsets padding;
  final TextStyle style;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final usePaperCurl = controller.preferences.state.value.pageTurningAnimation;
    final horizontalReader = HorizontalReadPage(
      controller.text.value,
      controller.images,
      initIndex: controller.initialHorizontalIndex,
      padding: padding,
      style: style,
      reverse: controller.preferences.state.value.direction == ReaderDirection.rightToLeft,
      isDualPage: controller.isDualPage,
      dualPageSpacing: controller.preferences.state.value.dualPageSpacing,
      controller: controller.pageController,
      pageTurningAnimation: controller.preferences.state.value.pageTurningAnimation,
      paraSpacing: controller.preferences.state.value.readerParaSpacing,
      paraIndent: controller.preferences.state.value.readerParaIndent,
      paperCurlController: controller.paperCurlController,
      backgroundColor: controller.preferences.bgColor ?? Theme.of(context).colorScheme.surface,
      backsideColor: Color.lerp(
        controller.preferences.bgColor ?? Theme.of(context).colorScheme.surface,
        Theme.of(context).colorScheme.surfaceTint,
        Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
      ),
      pageFooter: footer,
      onCenterTap: () => controller.showBar.value = !controller.showBar.value,
      onLeftTap: controller.prevPage,
      onRightTap: controller.nextPage,
      onReachStart: controller.prevChapter,
      onReachEnd: controller.nextChapter,
      onPageChanged: (index, max) {
        controller.currentIndex.value = index;
        controller.maxPage.value = max;
        if (max == 1 && index == 0) {
          //仅一页的情况下
          controller.horizontalProgress.value = 100;
          controller.setReadHistory(); //立即更新历史阅读记录
        } else if (max > 0) {
          controller.horizontalProgress.value = int.parse(((index + 1) / max * 100.0).toStringAsFixed(0)).clamp(0, 100);
          //由controller的debounce监听currentIndex变化，判断是否更新历史阅读记录
        }
      },
      onViewImage: (index) => Get.toNamed(RoutePath.photo, arguments: {"gallery_mode": true, "list": controller.images, "index": index}),
    );

    if (usePaperCurl) {
      return horizontalReader;
    }

    return EasyRefresh(
      header: MaterialHeader2(
        triggerOffset: 80,
        child: RefreshIndicatorBox(icon: Icons.arrow_circle_left_outlined),
      ),
      footer: MaterialFooter2(
        triggerOffset: 80,
        child: RefreshIndicatorBox(icon: Icons.arrow_circle_right_outlined),
      ),
      refreshOnStart: false,
      onRefresh: controller.prevChapter,
      onLoad: controller.nextChapter,
      child: horizontalReader,
    );
  }
}
