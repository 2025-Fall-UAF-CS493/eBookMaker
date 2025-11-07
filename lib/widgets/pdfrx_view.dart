import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PDF extends StatefulWidget {
  final ValueNotifier<bool> selectModeNotifier;
  final PdfDocumentRef? documentRef;

  const PDF({super.key, required this.selectModeNotifier, this.documentRef});

  @override
  State<PDF> createState() => _PDFState();
}

class _PDFState extends State<PDF> {
  final PdfViewerController _controller = PdfViewerController();
  bool get selectMode => widget.selectModeNotifier.value;

  Offset? _dragStart;
  Offset? _dragCurrent;
  OverlayEntry? _selectionOverlay;
  OverlayEntry? _entryLabel;
  final List<TextSelection> _selections = [];
  TextSelection? _pendingSelection;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PdfViewer(
          widget.documentRef!,
          controller: _controller,
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) {
              if (selectMode) {
                _dragStart = details.localPosition;
                _dragCurrent = _dragStart;
                _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!), false);
              }
            },
            onPanUpdate: (details) {
              if (selectMode) {
                _dragCurrent = details.localPosition;
                _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!), false);
              }
            },
            onPanEnd: (_) async {
              if (_dragStart != null && _dragCurrent != null && selectMode) {
                final rect = Rect.fromPoints(_dragStart!, _dragCurrent!);
                await _handleSelection(rect);
                _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!), true);
              }
              _dragStart = null;
              _dragCurrent = null;
            },
            onDoubleTap: () => _clearSelection(),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelButton() {
    return Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 191, 113, 250),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.label, color: Colors.white, size: 16),
            onPressed: () => _showLabelDialog(_pendingSelection!),
          ),
          const Text('Add Label', style: TextStyle(color: Colors.white, fontSize: 12)),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 16),
            onPressed: _clearSelection,
          ),
        ],
      ),
    );
  }

  void _updateSelectionOverlay(Rect localRect, bool end) {
    _selectionOverlay?.remove();
    _entryLabel?.remove();

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final globalRect = Rect.fromPoints(
      renderBox.localToGlobal(localRect.topLeft),
      renderBox.localToGlobal(localRect.bottomRight),
    );

    _selectionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: globalRect.left,
        top: globalRect.top,
        width: globalRect.width,
        height: globalRect.height,
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
    Overlay.of(context).insert(_selectionOverlay!);

    if (end) {
      _entryLabel = OverlayEntry(
        builder: (context) => Positioned(
          left: globalRect.left,
          top: globalRect.top - 50,
          child: _buildLabelButton(),
        ),
      );
      Overlay.of(context).insert(_entryLabel!);
    } else {
      _entryLabel = null;
    }
  }

  Future<void> _handleSelection(Rect selRect) async {
    if (!_controller.isReady) return;

    final topLeft = _controller.getPdfPageHitTestResult(
      selRect.topLeft,
      useDocumentLayoutCoordinates: false,
    );
    final bottomRight = _controller.getPdfPageHitTestResult(
      selRect.bottomRight,
      useDocumentLayoutCoordinates: false,
    );

    if (topLeft != null && bottomRight != null && topLeft.page == bottomRight.page) {
      final pdfRect = PdfRect(
        topLeft.offset.x, topLeft.offset.y,
        bottomRight.offset.x, bottomRight.offset.y,
      );

      PdfPageText? pageText;
      try {
        pageText = await topLeft.page.loadStructuredText();
      } catch (e) {
        debugPrint('Failed to load page text: $e');
        return;
      }

      final fragments = pageText.fragments.where((frag) => pdfRect.overlaps(frag.bounds)).toList();
      final selectedText = fragments.map((f) => f.text).join('');

      final newSelection = TextSelection(
        text: selectedText,
        bounds: pdfRect,
        pageNumber: topLeft.page.pageNumber,
        globalRect: _getGlobalRect(selRect),
        label: 'Selection ${_selections.length + 1}',
      );

      _pendingSelection = newSelection;

      debugPrint('Selected text: $selectedText');
    }
  }

  Rect _getGlobalRect(Rect localRect) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    return Rect.fromPoints(
      renderBox.localToGlobal(localRect.topLeft),
      renderBox.localToGlobal(localRect.bottomRight),
    );
  }

  void _showLabelDialog(TextSelection selection) {
    const List<String> labels = ['Title', 'Caption', 'Paragraph', 'Author'];
    String dropdownlabel = 'Title';

    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
    _pendingSelection = null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Label'),
          content: DropdownButton(
            value: dropdownlabel,
            items: labels
                .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                .toList(),
            onChanged: (String? newValue) {
              dropdownlabel = newValue!;
              Navigator.of(context).pop();
              _updateSelectionLabel(selection, dropdownlabel);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateSelectionLabel(selection, dropdownlabel);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _updateSelectionLabel(TextSelection selection, String newLabel) {
    _selections.add(selection.copyWith(label: newLabel.isEmpty ? 'Unlabeled' : newLabel));
    debugPrint('All Selections:');
    for (final s in _selections) {
      debugPrint('Label: ${s.label}, Text: ${s.text}');
    }
  }

  void _clearSelection() {
    _pendingSelection = null;
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
    debugPrint('Selection cleared');
  }
}

class TextSelection {
  final String text;
  final PdfRect bounds;
  final int pageNumber;
  final Rect globalRect;
  String label;

  TextSelection({
    required this.text,
    required this.bounds,
    required this.pageNumber,
    required this.globalRect,
    required this.label,
  });

  TextSelection copyWith({
    String? text,
    PdfRect? bounds,
    int? pageNumber,
    Rect? globalRect,
    String? label,
  }) {
    return TextSelection(
      text: text ?? this.text,
      bounds: bounds ?? this.bounds,
      pageNumber: pageNumber ?? this.pageNumber,
      globalRect: globalRect ?? this.globalRect,
      label: label ?? this.label,
    );
  }
}
