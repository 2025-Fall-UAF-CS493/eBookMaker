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
              color: Colors.blue.withOpacity(0.2),
              border: Border.all(color: Colors.blue, width: 2),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context)?.insert(_selectionOverlay!);
  }

  void _removeSelectionOverlay() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
  }

  Future<void> _handleSelection(Rect selRect) async {
    // Hit test top-left and bottom-right to get PDF coordinates
    final startHit = _controller.getPdfPageHitTestResult(
      selRect.topLeft,
      useDocumentLayoutCoordinates: true,
    );
    final endHit = _controller.getPdfPageHitTestResult(
      selRect.bottomRight,
      useDocumentLayoutCoordinates: true,
    );

    final page = startHit?.page ?? endHit?.page;
    if (page == null) {
      debugPrint('No PDF page found for selection.');
      return;
    }

    final pdfStart = startHit?.offset ?? PdfPoint(0, 0);
    final pdfEnd = endHit?.offset ?? PdfPoint(0, 0);

    // Normalize PDF rectangle: left <= right, bottom <= top
    final left = pdfStart.x < pdfEnd.x ? pdfStart.x : pdfEnd.x;
    final right = pdfStart.x > pdfEnd.x ? pdfStart.x : pdfEnd.x;
    final bottom = pdfStart.y < pdfEnd.y ? pdfStart.y : pdfEnd.y;
    final top = pdfStart.y > pdfEnd.y ? pdfStart.y : pdfEnd.y;

    final pdfRect = PdfRect(left, top, right, bottom);

    // Load page text
    PdfPageText? pageText;
    try {
      pageText = await page.loadText();
    } catch (e) {
      debugPrint('Failed to load page text: $e');
      return;
    }
    if (pageText == null) {
      debugPrint('No text on this page.');
      return;
    }

    // Find fragments inside rectangle
    final fragments = pageText.fragments.where((frag) => pdfRect.overlaps(frag.bounds)).toList();

    // Print selected text
    if (fragments.isEmpty) {
      debugPrint('No text selected.');
    } else {
      final selectedText = fragments.map((f) => f.text).join(' ');
      debugPrint('Selected text: $selectedText');
    }
  }
}
