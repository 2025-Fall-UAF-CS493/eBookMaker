import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart' as fs;


class PDF extends StatefulWidget {
  final ValueNotifier<bool> selectModeNotifier;
  final PdfDocumentRef? documentRef;
  final ValueNotifier<bool>? exportTrigger; // Add this

  const PDF({
    super.key, 
    required this.selectModeNotifier, 
    this.documentRef,
    this.exportTrigger,
  });

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
  void initState() {
    super.initState();
    // Listen for export triggers
    widget.exportTrigger?.addListener(_handleExportTrigger);
  }

  @override
  void dispose() {
    widget.exportTrigger?.removeListener(_handleExportTrigger);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PDF oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if the document changed
    if (widget.documentRef != oldWidget.documentRef) {
      _clearAllSelections(); // Clear highlights and selections
    }
  }

  void _handleExportTrigger() {
    if (widget.exportTrigger?.value == true) {
      exportPairedToText();
      // Reset the trigger
      widget.exportTrigger?.value = false;
    }
  }

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
        fontWeight: FontWeight.w900,
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
            language: 'Undefined' // Default langauge
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
    const List<String> languages = ['English', 'Not English', 'Other'];
    String dropdownLanguage = 'English';

    _selectionOverlay?.remove();
    //_selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
    //_pendingSelection = null;
  
    // Add label pop dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Add Label'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category dropdown
                  const Text('Category:'),
                  DropdownButton<String>(
                    value: dropdownlabel,
                    isExpanded: true,
                    items: labels.map((String label) {
                      return DropdownMenuItem(
                        value: label,
                        child: Text(label),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateDialog(() {
                        dropdownlabel = newValue!;
                      });
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Language dropdown
                  const Text('Language:'),
                  DropdownButton<String>(
                    value: dropdownLanguage,
                    isExpanded: true,
                    items: languages.map((String language) {
                      return DropdownMenuItem(
                        value: language,
                        child: Text(language),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateDialog(() {
                        dropdownLanguage = newValue!;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _updateSelectionLabel(selection, dropdownlabel, dropdownLanguage);
                    _finalizeBox(selection, dropdownlabel, dropdownLanguage);
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
      


  void _finalizeBox(TextSelection selection, String newLabel, String language) {
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
  void _updateSelectionLabel(TextSelection selection, String newLabel, String language) {
  
    _selections.add(selection.copyWith(
      label: newLabel.isEmpty ? 'Unlabeled' : newLabel,
      language: language));
    debugPrint('All Selections:');
    for (final s in _selections) {
      debugPrint('Label: ${s.label}, Text: ${s.text}');
    }
  }

  // Clear a selection
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

  void _clearAllSelections(){
    _selections.clear();
    _pdfMarkers.clear();
  }

  

  Future<void> exportPairedToText() async {
    final text = StringBuffer();
    
    text.writeln('PDF SELECTIONS');
    text.writeln('=' * 50);
    
    // Find the maximum length to iterate through both lists
    final maxLength = _selections.length > _pdfMarkers.length ? _selections.length : _pdfMarkers.length;
    
    for (int i = 0; i < maxLength; i++) {
      text.writeln('\nITEM ${i + 1}:');
      text.writeln('-' * 30);
      
      // Add selection if it exists
      if (i < _selections.length) {
        final s = _selections[i];
        text.writeln('SELECTION:');
        text.writeln('  Label: ${s.label}');
        text.writeln('  Language: ${s.language}'); 
        text.writeln('  Page: ${s.pageNumber}');
        text.writeln('  Text: "${s.text}"');
        text.writeln('  Position: (${s.bounds.left}, ${s.bounds.top}) to (${s.bounds.right}, ${s.bounds.bottom})');
      } else {
        text.writeln('SELECTION: [None]');
      }
      
      text.writeln(); // Empty line between selection and marker
      
      // Add marker if it exists 
      // Maybe don't need since the selection already has positioning??? 
      /*
      if (i < _pdfMarkers.length) {
        final m = _pdfMarkers[i];
        text.writeln('MARKER:');
        text.writeln('  Label: ${m.text}');
        text.writeln('  Page: ${m.pageNumber}');
        text.writeln('  Position: (${m.bounds.left}, ${m.bounds.top}) to (${m.bounds.right}, ${m.bounds.bottom})');
      } else {
        text.writeln('MARKER: [None]');
      }
      */
      
      if (i < maxLength - 1) {
        text.writeln('\n${'=' * 50}');
      }
    }
    
    await _saveTextToFile(text.toString());
  }

  Future<void> _saveTextToFile(String text) async {
    // For both mobile/desktop and web, use file_selector
    final location = await fs.getSaveLocation(
      suggestedName: 'pdf_annotations.txt',
    );
    
    if (location != null) {
      final file = fs.XFile.fromData(
        Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
        name: 'pdf_annotations.txt',
      );
      await file.saveTo(location.path);
    }
  }

}

// Data class to store selections with info
class TextSelection {
  final String text;
  final PdfRect bounds;
  final int pageNumber;
  final Rect globalRect;
  String label;
  String language;

  TextSelection({
    required this.text,
    required this.bounds,
    required this.pageNumber,
    required this.globalRect,
    required this.label,
    required this.language,
  });

  TextSelection copyWith({
    String? text,
    PdfRect? bounds,
    int? pageNumber,
    Rect? globalRect,
    String? label,
    String? language,
  }) {
    return TextSelection(
      text: text ?? this.text,
      bounds: bounds ?? this.bounds,
      pageNumber: pageNumber ?? this.pageNumber,
      globalRect: globalRect ?? this.globalRect,
      label: label ?? this.label,
      language: language ?? this.language, 
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
