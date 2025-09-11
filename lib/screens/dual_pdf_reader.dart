import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:manga_muli_language_viewer/utils/pdf_renderer.dart';
import 'package:manga_page_view/manga_page_view.dart';

class DualPdfReader extends StatefulWidget {
  final String pdfA;
  final String pdfB;
  final int pageCount;
  const DualPdfReader({
    super.key,
    required this.pdfA,
    required this.pdfB,
    required this.pageCount,
  });

  @override
  State<DualPdfReader> createState() => _DualPdfReaderState();
}

class _DualPdfReaderState extends State<DualPdfReader> {
  @override
  Widget build(BuildContext context) {
    return MangaPageView(
      direction: MangaPageViewDirection.right,
      mode: MangaPageViewMode.paged,
      pageCount: widget.pageCount,
      // Let the package manage zoom/pan; just return a widget for the page.
      pageBuilder: (context, index) {
        final pageNumber = index + 1; // convert 0-based -> 1-based

        // Load both pages in parallel
        final futureA = buildPdfPageRawImage(
          pathOrAsset: widget.pdfA,
          pageNumber: pageNumber,
        );
        final futureB = buildPdfPageRawImage(
          pathOrAsset: widget.pdfB,
          pageNumber: pageNumber,
        );
        return FutureBuilder<List<Widget>>(
          key: ValueKey('futures-$pageNumber-${widget.pdfA}-${widget.pdfB}'),
          future: Future.wait([futureA, futureB]),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final topPage = snap.data![0];
            final bottomPage = snap.data![1];

            // Single page without overlay? -> return Image.memory(aBytes, fit: BoxFit.contain)
            // With overlay/hover reveal:
            return _OverlayPage(
              key: ValueKey('overlay-$pageNumber'),
              top: topPage,
              bottom: bottomPage,
            );
          },
        );
      },
    );
  }
}

class _OverlayPage extends StatefulWidget {
  final Widget top, bottom;
  const _OverlayPage({required this.top, required this.bottom, super.key});

  @override
  State<_OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<_OverlayPage> {
  bool isPressed = false;
  late final FocusNode _focusNode;

  Offset? _pointer;
  final double _radius = 90;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) {
          setState(() => isPressed = !isPressed);
        }
      },
      focusNode: _focusNode,
      child: MouseRegion(
        onHover: (event) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            setState(() => _pointer = box.globalToLocal(event.position));
          }
        },
        onExit: (_) => setState(() => _pointer = null),
        child: Listener(
          onPointerDown: (event) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              setState(() => _pointer = box.globalToLocal(event.position));
            }
          },
          onPointerMove: (event) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              setState(() => _pointer = box.globalToLocal(event.position));
            }
          },
          onPointerUp: (_) => setState(() => _pointer = null),
          child: Stack(
            alignment: Alignment.center,
            children: [
              widget.bottom,
              // Top page with a circular clear hole (reveals bottom below)
              AnimatedOpacity(
                opacity: isPressed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: CustomPaint(
                  foregroundPainter: _RevealPainter(
                    pointer: _pointer,
                    radius: _radius,
                  ),
                  child: widget.top,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevealPainter extends CustomPainter {
  final Offset? pointer;
  final double radius;
  _RevealPainter({required this.pointer, required this.radius});
  @override
  void paint(Canvas canvas, Size size) {
    if (pointer == null) return; // nothing to reveal
    // Work on a separate layer so BlendMode.clear works as expected
    canvas.saveLayer(Offset.zero & size, Paint());
    // Draw a fully transparent rect to establish the layer; then punch a hole
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;
    canvas.drawCircle(pointer!, radius, clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RevealPainter old) =>
      old.pointer != pointer || old.radius != radius;
}
