import 'package:flutter/cupertino.dart';
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
  bool showSecondary = false; // toggled with spacebar
  List<String> _primaryImgs = [];
  List<String> _secondaryImgs = [];
  int _pageCount = 0;
  bool _loading = true;
  String? _error;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _service = MangaDexService(context.read<Dio>());
    _focus = FocusNode();
    _pageController = PageController();
    _load();
    // Ensure keyboard focus after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final imgsA = await _service.getChapterImageUrls(widget.primary.id,
          dataSaver: true);
      final imgsB = await _service.getChapterImageUrls(widget.secondary.id,
          dataSaver: true);
      final count = imgsA.length < imgsB.length
          ? imgsA.length
          : imgsB.length; // align by shortest
      setState(() {
        _primaryImgs = imgsA.take(count).toList();
        _secondaryImgs = imgsB.take(count).toList();
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
    if (!mounted || _pageCount == 0) return;
    final ctx = context;
    final candidates = <int>{index, index - 1, index + 1}
        .where((i) => i >= 0 && i < _pageCount)
        .toList();
    for (final i in candidates) {
      _precacheUrl(ctx, _primaryImgs[i]);
      _precacheUrl(ctx, _secondaryImgs[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focus,
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) {
          setState(() => showSecondary = !showSecondary);
          // Make sure the hidden layer is ready when toggled
          _prefetchAround(_currentPage);
        }
      },
      child: MacosScaffold(
        toolBar: ToolBar(
          title: Text('Reader - ${widget.primary.title}'),
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
              return PageView.builder(
                controller: _pageController,
                itemCount: _pageCount,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                  _prefetchAround(i);
                },
                itemBuilder: (context, index) {
                  final mq = MediaQuery.of(context);
                  final cacheWidth =
                      (mq.size.width * mq.devicePixelRatio).round();
                  final topUrl = _primaryImgs[index];
                  final bottomUrl = _secondaryImgs[index];
                  final topProvider =
                      ResizeImage(NetworkImage(topUrl), width: cacheWidth);
                  final bottomProvider =
                      ResizeImage(NetworkImage(bottomUrl), width: cacheWidth);

                  Widget buildImg(ImageProvider provider) {
                    return Image(
                      image: provider,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      // Lightweight progress indicator
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        final expected =
                            loadingProgress.expectedTotalBytes ?? 0;
                        final loaded = loadingProgress.cumulativeBytesLoaded;
                        final value = expected > 0 ? loaded / expected : null;
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

                  return Center(
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        // Top image (primary)
                        buildImg(topProvider),
                        
                        // Bottom image (secondary) stays mounted; just hide/show via opacity
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: showSecondary ? 1.0 : 0.0,
                          child: buildImg(bottomProvider),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
