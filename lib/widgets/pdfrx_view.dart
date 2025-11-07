import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PDF extends StatefulWidget {
  final ValueNotifier<bool> selectModeNotifier;

  const PDF({super.key, required this.selectModeNotifier}); 

  @override
  State<PDF> createState() => _PDFState();
}

class _PDFState extends State<PDF> {
  // Controller for managing PDF viewer operations
  final PdfViewerController _controller = PdfViewerController();
  bool get selectMode => widget.selectModeNotifier.value;

  @override
  void initState() {
    super.initState();
  }
  
  // Selection state variables
  Offset? _dragStart;
  Offset? _dragCurrent;
  OverlayEntry? _selectionOverlay;
  OverlayEntry? _entryLabel;
  
  // List to store all selections with their labels/data
  final List<TextSelection> _selections = [];
  // List to store all marker/highlight boxes with their data
  final List<PdfMarker> _pdfMarkers = [];

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
            params: PdfViewerParams(
              pagePaintCallbacks: [_paintMarkers],
            ),
          ),
          // Gesture detector overlay for handling selections
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
        ],
      ),
    );
  }

  // Copied from Pdfrx src code
  Rect _pdfRectToRectInDocument(PdfRect pdfRect, {required PdfPage page, required Rect pageRect}) {
    final rotated = pdfRect.rotate(page.rotation.index, page);
    final scale = pageRect.height / page.height;
    return Rect.fromLTRB(
      rotated.left * scale,
      (page.height - rotated.top) * scale,
      rotated.right * scale,
      (page.height - rotated.bottom) * scale,
    ).translate(pageRect.left, pageRect.top);
  }

  // Shows the markers on PDF pages
  void _paintMarkers(Canvas canvas, Rect pageRect, PdfPage page) {
    final markers = _pdfMarkers.where((marker) => marker.pageNumber == page.pageNumber).toList();
    if (markers.isEmpty) return;
    
    for (final marker in markers) {
      final paint = Paint()
        ..color = marker.color
        ..style = PaintingStyle.fill;

      final documentRect = _pdfRectToRectInDocument(
        marker.bounds, 
        page: page, 
        pageRect: pageRect
      );
      canvas.drawRect(documentRect, paint);
    }
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
          const Text(
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
        // Create PDF rectangle from selection coordinates
        final pdfRect = PdfRect(topLeft.offset.x, topLeft.offset.y,
                                bottomRight.offset.x, bottomRight.offset.y);

        // Load page text
        PdfPageText? pageText;
        try {
          pageText = await topLeft.page.loadStructuredText();
        } catch (e) {
          debugPrint('Failed to load page text: $e');
          return;
        }

        final fragments = pageText.fragments
            .where((frag) => pdfRect.overlaps(frag.bounds))
            .toList();

        final selectedText = fragments.map((f) => f.text).join('');
        
        if (fragments.isNotEmpty) {
          // Create a new selection item
          final newSelection = TextSelection(
            text: selectedText,
            bounds: pdfRect,
            pageNumber: topLeft.page.pageNumber,
            globalRect: _getGlobalRect(selRect),
            label: 'Selection ${_selections.length + 1}', // Default label
          );
          
          // Create a new marker item
          final newMarker = PdfMarker(
            color: const Color.fromARGB(255, 45, 246, 239).withAlpha(70),
            bounds: pdfRect,
            pageNumber: topLeft.page.pageNumber,
          );
          
          // Set as pending selection to show label button
          _pendingSelection = newSelection;
          _pdfMarkers.add(newMarker);

          // Print selected text and markers
          debugPrint('Selected text: $selectedText');
          debugPrint('Total selections: ${_selections.length+1}');
          debugPrint('Total markers: ${_pdfMarkers.length}');
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
    const List<String> labels = ['Title', 'Caption', 'Paragraph', 'Author'];
    String dropdownlabel = 'Title';

    // Clear the selection overlay and pending selection when dialog is shown
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
            hint: const Text("Select a category"),
            items: 
              labels.map((String labels) {
                return DropdownMenuItem(value: labels, child: Text(labels));
                }
              ).toList(), 
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

  // Update/add the label of a specific selection
  void _updateSelectionLabel(TextSelection selection, String newLabel) {
  
    _selections.add(selection.copyWith(label: newLabel.isEmpty ? 'Unlabeled' : newLabel));
    
    // Print all selections
    debugPrint('All Selections:');
    for (final selection in _selections) {
      debugPrint('Label: ${selection.label}, Text: ${selection.text}');
    }
  }

  // Clears selection and removes the selection overlay
  void _clearSelection() {

    if (_pendingSelection != null) {
      _pdfMarkers.removeLast();
      _pendingSelection = null;
    }
    
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

// Data class to store marker selections with info
class PdfMarker {
  final Color color;
  final PdfRect bounds;
  final int pageNumber;

  PdfMarker({
    required this.color,
    required this.bounds,
    required this.pageNumber,
  });
}
