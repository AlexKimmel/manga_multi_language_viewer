import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import '../models/chapter.dart';
import '../services/mangadx_service.dart';

class DualChapterReader extends StatefulWidget {
  final Chapter primary;
  final Chapter secondary;
  const DualChapterReader(
      {super.key, required this.primary, required this.secondary});

  @override
  State<DualChapterReader> createState() => _DualChapterReaderState();
}

class _DualChapterReaderState extends State<DualChapterReader> {
  late final MangaDexService _service;
  late final FocusNode _focus;
  late final PageController _pageController;
  late final TransformationController _zoomController;
  late final ScrollController _thumbPrimaryCtrl;
  late final ScrollController _thumbSecondaryCtrl;
  bool _syncingThumbs = false;

  bool _showBottomBar = false;
  static const double _hoverRevealHeight = 25.0;
  static const double _thumbItemExtent =
      90.0; // width per thumbnail incl. spacing
  static const double _thumbRowHeight = 70.0; // height of each row
  bool _isZoomed = false;
  bool showSecondary = false; // toggled with spacebar
  List<String> _primaryImgs = [];
  List<String> _secondaryImgs = [];
  // Soft-hide state per language
  final Set<int> _hiddenPrimary = <int>{};
  final Set<int> _hiddenSecondary = <int>{};
  List<int> _visiblePrimary = <int>[];
  List<int> _visibleSecondary = <int>[];
  int _pageCount = 0;
  bool _loading = true;
  String? _error;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController.addListener(_onZoomChanged);
    _focus = FocusNode();

    _pageController = PageController();
    _thumbPrimaryCtrl = ScrollController();
    _thumbSecondaryCtrl = ScrollController();

    _thumbPrimaryCtrl.addListener(_onPrimaryThumbScroll);
    _thumbSecondaryCtrl.addListener(_onSecondaryThumbScroll);
    _service = MangaDexService(context.read<Dio>());

    _load();
    // Ensure keyboard focus after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    _pageController.dispose();
    _zoomController.dispose();
    _thumbPrimaryCtrl.removeListener(_onPrimaryThumbScroll);
    _thumbSecondaryCtrl.removeListener(_onSecondaryThumbScroll);
    _thumbPrimaryCtrl.dispose();
    _thumbSecondaryCtrl.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final z = scale > 1.0001;
    if (z != _isZoomed) {
      setState(() {
        _isZoomed = z;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final imgsA = await _service.getChapterImageUrls(
        widget.primary.id,
        dataSaver: true,
      );
      final imgsB = await _service.getChapterImageUrls(
        widget.secondary.id,
        dataSaver: true,
      );
      final count = imgsA.length < imgsB.length ? imgsA.length : imgsB.length;
      setState(() {
        _primaryImgs = imgsA.take(count).toList();
        _secondaryImgs = imgsB.take(count).toList();
        _visiblePrimary = List<int>.generate(count, (i) => i);
        _visibleSecondary = List<int>.generate(count, (i) => i);
        _pageCount = count;
        _loading = false;
      });
      // Prefetch current and next page once we have data
      _prefetchAround(0);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Precache helper for a single image URL at an approximate display width
  Future<void> _precacheUrl(BuildContext context, String url) async {
    if (url.isEmpty) return;
    final mq = MediaQuery.of(context);
    final int cacheWidth = (mq.size.width * mq.devicePixelRatio).round();
    final provider = ResizeImage(NetworkImage(url), width: cacheWidth);
    try {
      await precacheImage(provider, context);
    } catch (_) {
      // Ignore individual prefetch failures
    }
  }

  // Prefetch current, previous, and next pages for both languages
  void _prefetchAround(int index) {
    if (!mounted) return;
    final minLen = _visiblePrimary.length < _visibleSecondary.length
        ? _visiblePrimary.length
        : _visibleSecondary.length;
    if (minLen == 0) return;
    final ctx = context;
    final candidates = <int>{index, index - 1, index + 1}
        .where((i) => i >= 0 && i < minLen)
        .toList();
    for (final i in candidates) {
      final pi = _visiblePrimary[i];
      final si = _visibleSecondary[i];
      _precacheUrl(ctx, _primaryImgs[pi]);
      _precacheUrl(ctx, _secondaryImgs[si]);
    }
  }

  void _recomputeVisibleAndClamp() {
    final total = _primaryImgs.length < _secondaryImgs.length
        ? _primaryImgs.length
        : _secondaryImgs.length;
    // Ensure visible lists match total length (guard for reloads)
    if (_visiblePrimary.length != total) {
      _visiblePrimary = List<int>.generate(total, (i) => i)
        ..removeWhere((i) => _hiddenPrimary.contains(i));
    } else {
      _visiblePrimary = List<int>.generate(total, (i) => i)
        ..removeWhere((i) => _hiddenPrimary.contains(i));
    }
    if (_visibleSecondary.length != total) {
      _visibleSecondary = List<int>.generate(total, (i) => i)
        ..removeWhere((i) => _hiddenSecondary.contains(i));
    } else {
      _visibleSecondary = List<int>.generate(total, (i) => i)
        ..removeWhere((i) => _hiddenSecondary.contains(i));
    }

    final newCount = _visiblePrimary.length < _visibleSecondary.length
        ? _visiblePrimary.length
        : _visibleSecondary.length;
    _pageCount = newCount;
    if (_currentPage >= _pageCount) {
      _currentPage = _pageCount > 0 ? _pageCount - 1 : 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage);
      }
    }
  }

  void _toggleHide({required bool isPrimary, required int originalIndex}) {
    setState(() {
      final setRef = isPrimary ? _hiddenPrimary : _hiddenSecondary;
      if (setRef.contains(originalIndex)) {
        setRef.remove(originalIndex);
      } else {
        setRef.add(originalIndex);
      }
      _recomputeVisibleAndClamp();
    });
    // Keep thumbnails roughly centered on the current mapping
    if (_pageCount > 0) {
      final ap = _currentPage < _visiblePrimary.length
          ? _visiblePrimary[_currentPage]
          : null;
      final as = _currentPage < _visibleSecondary.length
          ? _visibleSecondary[_currentPage]
          : null;
      if (ap != null || as != null) {
        _scrollThumbsToMapped(
            primaryOriginalIndex: ap, secondaryOriginalIndex: as);
      }
    }
  }

  // Keep the two thumbnail rows in sync
  void _onPrimaryThumbScroll() {
    if (_syncingThumbs) return;
    if (!_thumbSecondaryCtrl.hasClients) return;
    _syncingThumbs = true;
    _thumbSecondaryCtrl.jumpTo(
      _thumbPrimaryCtrl.offset.clamp(
        0.0,
        _thumbSecondaryCtrl.position.maxScrollExtent,
      ),
    );
    _syncingThumbs = false;
  }

  void _onSecondaryThumbScroll() {
    if (_syncingThumbs) return;
    if (!_thumbPrimaryCtrl.hasClients) return;
    _syncingThumbs = true;
    _thumbPrimaryCtrl.jumpTo(
      _thumbSecondaryCtrl.offset.clamp(
        0.0,
        _thumbPrimaryCtrl.position.maxScrollExtent,
      ),
    );
    _syncingThumbs = false;
  }

  // (replaced by _scrollThumbsToMapped)

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space) {
          setState(() => showSecondary = !showSecondary);

          // Make sure the hidden layer is ready when toggled
          _prefetchAround(_currentPage);
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (_currentPage < _pageCount - 1) {
            _pageController.nextPage(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut);
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (_currentPage > 0) {
            _pageController.previousPage(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MacosScaffold(
        toolBar: ToolBar(
          title: const Text('Reader'),
          leading: MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        children: [
          ContentArea(
            builder: (context, controller) {
              if (_loading) {
                return const Center(child: ProgressCircle(radius: 20));
              }
              if (_error != null) {
                return Center(child: Text('Error: $_error'));
              }
              return Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: _pageCount,
                    physics: _isZoomed
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: (i) {
                      setState(() => _currentPage = i);
                      _prefetchAround(i);
                      // reset zoom on page change
                      _zoomController.value = Matrix4.identity();
                      // ensure thumbnails track the current page
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final ap = _currentPage < _visiblePrimary.length
                            ? _visiblePrimary[_currentPage]
                            : null;
                        final as = _currentPage < _visibleSecondary.length
                            ? _visibleSecondary[_currentPage]
                            : null;
                        _scrollThumbsToMapped(
                            primaryOriginalIndex: ap,
                            secondaryOriginalIndex: as);
                      });
                    },
                    itemBuilder: (context, index) {
                      final mq = MediaQuery.of(context);
                      final cacheWidth =
                          (mq.size.width * mq.devicePixelRatio).round();
                      final pi = _visiblePrimary.isNotEmpty &&
                              index < _visiblePrimary.length
                          ? _visiblePrimary[index]
                          : 0;
                      final si = _visibleSecondary.isNotEmpty &&
                              index < _visibleSecondary.length
                          ? _visibleSecondary[index]
                          : 0;
                      final topUrl =
                          _primaryImgs.isNotEmpty ? _primaryImgs[pi] : '';
                      final bottomUrl =
                          _secondaryImgs.isNotEmpty ? _secondaryImgs[si] : '';
                      final topProvider =
                          ResizeImage(NetworkImage(topUrl), width: cacheWidth);
                      final bottomProvider = ResizeImage(
                          NetworkImage(bottomUrl),
                          width: cacheWidth);

                      Widget buildImg(ImageProvider provider) {
                        return Image(
                          image: provider,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            final expected =
                                loadingProgress.expectedTotalBytes ?? 0;
                            final loaded =
                                loadingProgress.cumulativeBytesLoaded;
                            final value =
                                expected > 0 ? loaded / expected : null;
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const ProgressCircle(radius: 16),
                                  if (value != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                          '${(value * 100).toStringAsFixed(0)}%'),
                                    ),
                                ],
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(CupertinoIcons.exclamationmark_triangle,
                                    size: 24),
                                SizedBox(height: 8),
                                Text('Failed to load image'),
                              ],
                            ),
                          ),
                        );
                      }

                      return InteractiveViewer(
                        transformationController: _zoomController,
                        minScale: 1.0,
                        maxScale: 10.0,
                        panEnabled: _isZoomed,
                        scaleEnabled: true,
                        boundaryMargin: const EdgeInsets.all(0),
                        clipBehavior: Clip.none,
                        onInteractionEnd: (details) {
                          final scale =
                              _zoomController.value.getMaxScaleOnAxis();
                          if (scale < 1.0001) {
                            _zoomController.value = Matrix4.identity();
                          }
                        },
                        child: Center(
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              buildImg(topProvider),
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 150),
                                opacity: showSecondary ? 1.0 : 0.0,
                                child: buildImg(bottomProvider),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Global thin hover strip at the bottom to reveal the bar
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _hoverRevealHeight,
                    child: MouseRegion(
                      opaque: false,
                      onEnter: (_) {
                        if (!_showBottomBar) {
                          setState(() => _showBottomBar = true);
                        }
                      },
                      onHover: (_) {
                        if (!_showBottomBar) {
                          setState(() => _showBottomBar = true);
                        }
                      },
                      onExit: (_) {
                        if (_showBottomBar) {
                          setState(() => _showBottomBar = false);
                        }
                      },
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  // Global bottom bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: MouseRegion(
                      onEnter: (_) {
                        if (!_showBottomBar) {
                          setState(() => _showBottomBar = true);
                        }
                      },
                      onExit: (_) {
                        if (_showBottomBar) {
                          setState(() => _showBottomBar = false);
                        }
                      },
                      child: IgnorePointer(
                        ignoring: !_showBottomBar,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          offset:
                              _showBottomBar ? Offset.zero : const Offset(0, 1),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            opacity: _showBottomBar ? 1.0 : 0.0,
                            child: _buildThumbnailBar(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailBar(BuildContext context) {
    const barHeight = (_thumbRowHeight * 2) + 16; // padding
    // ignore: deprecated_member_use
    final bg = Colors.black.withOpacity(0.55);
    return Container(
      height: barHeight + 4, // magic number here to avoid clipping
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildThumbRow(
            _primaryImgs,
            isPrimary: true,
            activeOriginalIndex: _currentPage < _visiblePrimary.length
                ? _visiblePrimary[_currentPage]
                : -1,
          ),
          const SizedBox(height: 4),
          _buildThumbRow(
            _secondaryImgs,
            isPrimary: false,
            activeOriginalIndex: _currentPage < _visibleSecondary.length
                ? _visibleSecondary[_currentPage]
                : -1,
          ),
        ],
      ),
    );
  }

  Widget _buildThumbRow(List<String> urls,
      {required bool isPrimary, required int activeOriginalIndex}) {
    final controller = isPrimary ? _thumbPrimaryCtrl : _thumbSecondaryCtrl;
    return SizedBox(
      height: _thumbRowHeight,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        itemExtent: _thumbItemExtent + 2, // include spacing between items
        itemCount: urls.length,
        itemBuilder: (context, i) {
          final isHidden = isPrimary
              ? _hiddenPrimary.contains(i)
              : _hiddenSecondary.contains(i);
          final isActive = i == activeOriginalIndex;
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: _thumbItemExtent + (i == urls.length - 1 ? 0 : 8),
              height: _thumbRowHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (isHidden) return; // disabled while hidden
                    if (_pageController.hasClients) {
                      // map original index to page position in its visible list
                      final visList =
                          isPrimary ? _visiblePrimary : _visibleSecondary;
                      final targetPos = visList.indexOf(i);
                      if (targetPos >= 0 && targetPos < _pageCount) {
                        _pageController.animateToPage(
                          targetPos,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        );
                      } else if (targetPos >= 0 && _pageCount > 0) {
                        _pageController.animateToPage(
                          _pageCount - 1,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        );
                      }
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: _thumbItemExtent,
                    height: _thumbRowHeight,
                    decoration: BoxDecoration(
                      // ignore: deprecated_member_use
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF4FC3F7)
                            : (isHidden ? Colors.white12 : Colors.white24),
                        width: isActive ? 2.0 : 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildThumbImage(
                      url: urls[i],
                      isPrimary: isPrimary,
                      originalIndex: i,
                      isHidden: isHidden,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThumbImage({
    required String url,
    required bool isPrimary,
    required int originalIndex,
    required bool isHidden,
  }) {
    // Create a small resized image to save memory/bandwidth
    final provider = ResizeImage(
      NetworkImage(url),
      width:
          (_thumbItemExtent * MediaQuery.of(context).devicePixelRatio).round(),
    );
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        ColorFiltered(
          colorFilter: isHidden
              ? const ColorFilter.mode(Colors.black45, BlendMode.darken)
              : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Icon(CupertinoIcons.exclamationmark_triangle,
                  size: 16, color: Colors.white70),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: () {
              _toggleHide(isPrimary: isPrimary, originalIndex: originalIndex);
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                isHidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 16,
                color: isHidden ? Colors.redAccent : Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Scroll the thumbnail rows to keep provided original indices visible
  void _scrollThumbsToMapped(
      {int? primaryOriginalIndex, int? secondaryOriginalIndex}) {
    if (_thumbPrimaryCtrl.hasClients && primaryOriginalIndex != null) {
      final viewport = _thumbPrimaryCtrl.position.viewportDimension;
      final target = (primaryOriginalIndex * _thumbItemExtent) -
          (viewport / 2) +
          (_thumbItemExtent / 2);
      final clamped =
          target.clamp(0.0, _thumbPrimaryCtrl.position.maxScrollExtent);
      _thumbPrimaryCtrl.animateTo(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    if (_thumbSecondaryCtrl.hasClients && secondaryOriginalIndex != null) {
      final viewport = _thumbSecondaryCtrl.position.viewportDimension;
      final target = (secondaryOriginalIndex * _thumbItemExtent) -
          (viewport / 2) +
          (_thumbItemExtent / 2);
      final clamped =
          target.clamp(0.0, _thumbSecondaryCtrl.position.maxScrollExtent);
      _thumbSecondaryCtrl.animateTo(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }
}
