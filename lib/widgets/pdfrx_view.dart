import 'dart:ui' as ui;

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
  // List to store all marker/highlight boxes with their data
  final List<PdfMarker> _pdfMarkers = [];

  // Track the most recent selection for labeling
  TextSelection? _pendingSelection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PdfViewer(
            widget.documentRef!,
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

      final paragraph = _buildParagraph(marker.text, documentRect.width, fontSize: 10, color: Colors.black,);
      canvas.drawParagraph(paragraph, Offset(documentRect.left + 3, documentRect.top - 12));
    }
  }

  ui.Paragraph _buildParagraph(String text, double maxWidth, {double fontSize = 14, Color color = const Color(0xFF000000)}) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: fontSize,
        maxLines: 1,
      ),
    )
      ..pushStyle(ui.TextStyle(color: color))
      ..addText(text);

    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
    return paragraph;
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
            onPressed: () => _showLabelDialog(_pendingSelection!),
          ),
          const Text(
            'Add Label',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 4),
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
              color: const ui.Color.fromARGB(111, 33, 149, 243),
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
          

          
          // Set as pending selection to show label button
          _pendingSelection = newSelection;

          // Print selected text and markers
          debugPrint('Selected text: $selectedText');
          debugPrint('Total selections: ${_selections.length+1}');
          debugPrint('Total markers: ${_pdfMarkers.length}');
        }
      }
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
    //_selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
    //_pendingSelection = null;
  
    

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
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
                  setStateDialog(() { 
                    dropdownlabel = newValue!;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _updateSelectionLabel(selection, dropdownlabel);
                    _finalizeBox(selection, dropdownlabel);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          }
        );
      },
    );
  }


  void _finalizeBox(TextSelection selection, String newLabel) {
    // Create a new marker item
    final newMarker = PdfMarker(
      color: const Color.fromARGB(255, 45, 246, 239).withAlpha(70),
      bounds: selection.bounds,
      pageNumber: selection.pageNumber,
      text: newLabel
    );
    
    _pdfMarkers.add(newMarker);
    //_selectionOverlay?.remove();
    _selectionOverlay = null;
    _pendingSelection = null;
  }

  // Update/add the label of a specific selection
  void _updateSelectionLabel(TextSelection selection, String newLabel) {
  
    _selections.add(selection.copyWith(label: newLabel.isEmpty ? 'Unlabeled' : newLabel));
    debugPrint('All Selections:');
    for (final s in _selections) {
      debugPrint('Label: ${s.label}, Text: ${s.text}');
    }
  }

  void _clearSelection() {

    if (_pendingSelection != null) {
      //_pdfMarkers.removeLast();
      _pendingSelection = null;
    }
    
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

// Data class to store marker selections with info
class PdfMarker {
  final Color color;
  final PdfRect bounds;
  final int pageNumber;
  final String text;

  PdfMarker({
    required this.color,
    required this.bounds,
    required this.pageNumber,
    required this.text,
  });
}
