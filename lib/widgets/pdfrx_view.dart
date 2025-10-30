import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PDF extends StatefulWidget {
  final bool selectMode; // Track if select mode is on
  final int currentPage; // Track page number
  // Has page number, maybe don't need????
  const PDF({super.key, required this.selectMode, required this.currentPage}); 

  @override
  State<PDF> createState() => _PDFState();
}

class _PDFState extends State<PDF> {
  // Controller for managing PDF viewer operations
  final PdfViewerController _controller = PdfViewerController();
  
  // Selection state variables
  Offset? _dragStart;
  Offset? _dragCurrent;
  OverlayEntry? _selectionOverlay;
  OverlayEntry? _entryLabel;
  
  // List to store all selections with their labels/data
  final List<TextSelection> _selections = [];

  // Track the most recent selection for labeling
  TextSelection? _pendingSelection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PdfViewer.asset(
            'assets/sample.pdf',
            controller: _controller,
          ),
          // Gesture detector overlay for handling selections
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                if (widget.selectMode) {
                  _dragStart = details.localPosition;
                  _dragCurrent = _dragStart;
                  _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!), false);
                }
              },
              onPanUpdate: (details) {
                if (widget.selectMode) {
                  _dragCurrent = details.localPosition;
                  _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!), false);
                }
              },
              onPanEnd: (_) async {
                if (_dragStart != null && _dragCurrent != null && widget.selectMode) {
                  final rect = Rect.fromPoints(_dragStart!, _dragCurrent!);
                  await _handleSelection(rect);
                  _updateSelectionOverlay(Rect.fromPoints(_dragStart!, _dragCurrent!), true);
                }
                // Keep overlay for labeling
                _dragStart = null;
                _dragCurrent = null;
              },
              onDoubleTap: () {
                // Double tap to clear selections instead
                _clearSelection();
              },
            ),
          ),
          // Label button that appears when a selection is made
          // if (_pendingSelection != null)
          //   Positioned(
          //     bottom: _pendingSelection!.,
          //     left: _pendingSelection!.globalRect.left,
          //     child: _buildLabelButton(),
          //   ),
        ],
      ),
    );
  }

  // Build the label button widget
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
            onPressed: () {
              _showLabelDialog(_pendingSelection!);
            },
          ),
          Text(
            'Add Label',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 16),
            onPressed: () {
              _clearSelection();
            },
          ),
        ],
      ),
    );
  }

  void _updateSelectionOverlay(Rect localRect, bool end) {
    _selectionOverlay?.remove();
    _entryLabel?.remove();

    // Convert local coordinates to global coordinates for overlay positioning
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final globalTopLeft = renderBox.localToGlobal(localRect.topLeft);
    final globalBottomRight = renderBox.localToGlobal(localRect.bottomRight);
    final globalRect = Rect.fromPoints(globalTopLeft, globalBottomRight);

    _selectionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: globalRect.left,
        top: globalRect.top,
        width: globalRect.width,
        height: globalRect.height,
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

    if (end) {
      _entryLabel = OverlayEntry(
        builder: (context) => Positioned(
          left: globalRect.left,
          top: globalRect.top - 50,
          child: _buildLabelButton(),
        )
      );
      Overlay.of(context).insert(_entryLabel!);
    } else {
      _entryLabel = null;
    }
  }

  Future<void> _handleSelection(Rect selRect) async {
    if (_controller.isReady) {

      // Convert screen coordinates to PDF page coordinates
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

        // Create PDF rectangle from selection coordinates
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

        if (fragments.isNotEmpty) {
          final selectedText = fragments.map((f) => f.text).join('');
          
          // Create a new selection item
          final newSelection = TextSelection(
            text: selectedText,
            bounds: pdfRect,
            pageNumber: topLeft.page.pageNumber,
            globalRect: _getGlobalRect(selRect),
            label: 'Selection ${_selections.length + 1}', // Default label
          );
          
          // Set as pending selection to show label button
          // Keep the overlay visible until user clicks label button
          setState(() {
            _pendingSelection = newSelection;
          });
          
          // Print selected text
          debugPrint('Selected text: $selectedText');
          debugPrint('Selected area: $pdfRect');
          debugPrint('Total selections: ${_selections.length+1}');
        }
      }
    }
  }

  // Converts local coordinates to global screen coordinates
  Rect _getGlobalRect(Rect localRect) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final globalTopLeft = renderBox.localToGlobal(localRect.topLeft);
    final globalBottomRight = renderBox.localToGlobal(localRect.bottomRight);
    return Rect.fromPoints(globalTopLeft, globalBottomRight);
  }

  // Shows popup for user to input a custom label for the selection
  void _showLabelDialog(TextSelection selection) {

    // Clear the selection overlay and pending selection when dialog is shown
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
    
    setState(() {
      _pendingSelection = null;
    });
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String label = selection.label;
        return AlertDialog(
          title: const Text('Add Label'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter label for this selection'),
            onChanged: (value) {
              label = value;
            },
            onSubmitted: (value) {
              Navigator.of(context).pop();
              _updateSelectionLabel(selection, value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateSelectionLabel(selection, label);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Update/add the label of a specific selection
  void _updateSelectionLabel(TextSelection selection, String newLabel) {
    setState(() {
      _selections.add(selection.copyWith(label: newLabel.isEmpty ? 'Unlabeled' : newLabel));
    });
    
    // Print all selections
    debugPrint('All Selections:');
    for (final selection in _selections) {
      debugPrint('Label: ${selection.label}, Text: ${selection.text}');
    }
    
  }

  // Clears selection and removes the selection overlay
  void _clearSelection() {
    setState(() {
      _pendingSelection = null;
    });
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
    debugPrint('Selection cleared');
  }

}

// Data class to store text selections with labels
class TextSelection {
  final String text;        // The selected text
  final PdfRect bounds;     // Selection rect in PDF coordinates
  final int pageNumber;     // Page number where selection was made
  final Rect globalRect;    // Selection rect in screen coordinates
  String label;             // Label for the selection

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