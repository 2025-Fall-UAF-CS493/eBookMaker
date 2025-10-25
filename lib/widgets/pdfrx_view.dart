import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PDF extends StatefulWidget {
  const PDF({super.key});

  @override
  State<PDF> createState() => _PDFState();
}

class _PDFState extends State<PDF> {
  final PdfViewerController _controller = PdfViewerController();

  Offset? _dragStart;
  Offset? _dragCurrent;
  OverlayEntry? _selectionOverlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PdfViewer.asset(
            'assets/sample.pdf',
            controller: _controller,
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                _dragStart = details.localPosition;
                _dragCurrent = _dragStart;
                _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!));
              },
              onPanUpdate: (details) {
                _dragCurrent = details.localPosition;
                _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!));
              },
              onPanEnd: (_) async {
                if (_dragStart != null && _dragCurrent != null) {
                  final rect = Rect.fromPoints(_dragStart!, _dragCurrent!);
                  await _handleSelection(rect);
                }
                _removeSelectionOverlay();
                _dragStart = null;
                _dragCurrent = null;
              },
            ),
          ),
        ],
      ),
    );
  }

  void _updateSelectionOverlay(Rect rect) {
    _selectionOverlay?.remove();
    _selectionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              border: Border.all(color: Colors.blue, width: 2),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_selectionOverlay!);
  }

  void _removeSelectionOverlay() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
  }

  Future<void> _handleSelection(Rect selRect) async {

    if (_controller.isReady) {

      final topLeft = _controller.getPdfPageHitTestResult(
        selRect.topLeft,
        useDocumentLayoutCoordinates: false,
      );

      final bottomRight = _controller.getPdfPageHitTestResult(
        selRect.bottomRight,
        useDocumentLayoutCoordinates: false,
      );

      if (topLeft != null && bottomRight != null && topLeft.page == bottomRight.page) {

        // final left = topLeft.offset.x < dragEnd.offset.x ? topLeft.offset.x : dragEnd.offset.x;
        // final right = topLeft.offset.x > dragEnd.offset.x ? topLeft.offset.x : dragEnd.offset.x;
        // final bottom = topLeft.offset.y < dragEnd.offset.y ? topLeft.offset.y : dragEnd.offset.y;
        // final top = topLeft.offset.y > dragEnd.offset.y ? topLeft.offset.y : dragEnd.offset.y;
        //
        // final pdfRect = PdfRect(left, top, right, bottom);
        final pdfRect = PdfRect(topLeft.offset.x, topLeft.offset.y,
                                bottomRight.offset.x, bottomRight.offset.y);

        // Load page text
        PdfPageText? pageText;
        try {
          pageText = await topLeft.page.loadText();
        } catch (e) {
          debugPrint('Failed to load page text: $e');
          return;
        }

        // Find fragments inside rectangle
        final fragments = pageText.fragments.where((frag) => pdfRect.overlaps(frag.bounds)).toList();

        // Print selected text
        if (fragments.isEmpty) {
          debugPrint('No text selected.');
        } else {
          final selectedText = "<text>${fragments.map((f) => f.text).join('')}</text>";
          debugPrint('Selected text: $selectedText');
        }
      }
    }

  }
}
