import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image/image.dart' as img;

class PDF extends StatefulWidget {
  final ValueNotifier<bool> selectModeNotifier;
  final PdfDocumentRef? documentRef;
  final ValueNotifier<bool>? exportTrigger; 

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
  // Controller and State vars
  final PdfViewerController _controller = PdfViewerController();
  bool get selectMode => widget.selectModeNotifier.value;

  // Selection state
  Offset? _dragStart;
  Offset? _dragCurrent;
  OverlayEntry? _selectionOverlay;
  OverlayEntry? _entryLabel;

  final Map<int, TextSelection> _selections = {};
  // List to store all marker/highlight boxes with their data
  final List<PdfMarker> _pdfMarkers = [];
  final List<ImageAnnotation> _imageAnnotations = [];

  int _indexCount = 0;

  // Track the most recent selection for labeling
  TextSelection? _pendingSelection;
  Map<String, dynamic>? _pendingSelectionData;
  Map<String, dynamic>? _pendingImageData;

  // =========================
  // === LIFECYCLE METHODS ===
  // =========================

  final _hasSelected = ValueNotifier<PdfMarker?>(null);

  @override
  void initState() {
    super.initState();
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
    if (widget.documentRef != oldWidget.documentRef) {
      _clearAllSelections();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Stack(
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

                    onTapDown: (details) async {
                      final pdfTap = _controller.getPdfPageHitTestResult(
                        details.localPosition,
                        useDocumentLayoutCoordinates: false,
                      );

                      for (PdfMarker marker in _pdfMarkers) {
                        if (pdfTap != null && marker.bounds.containsPoint(pdfTap.offset)) {
                          _onMarkerTapped(marker);
                          return;
                        }
                      }
                    },

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
          ),

          // Sidebar
          ValueListenableBuilder<PdfMarker?>(
            valueListenable: _hasSelected,
            builder: (_, hasSelected, _) {

              final visible = hasSelected != null;

              return SizedBox(
                width: visible ? 250 : 0,
                child: Column (
                  children: [

                    Spacer(),

                    Text(visible ? "Text" : ""),
                    Expanded(
                      flex: 4,
                      child: Card(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: Text(!visible ? "" : _selections[_hasSelected.value!.index]!.text),
                          ),
                        )
                      )
                    ),

                    Spacer(),

                    Text(visible ? "Label" : ""),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Text(!visible ? "" : _hasSelected.value!.text),
                        ),
                      )
                    ),

                    Spacer(
                      flex: 5,
                    ),

                    Center(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                        ),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text("Delete Selection"),
                        onPressed: () => deleteSelection(),
                      ),
                    ),

                    Spacer(),
                  ],
                )
              );
            }
          )
        ]
      )
    );
  }
  
  // ==========================
  // === SELECTION HANDLING ===
  // ==========================

  void _onMarkerTapped(PdfMarker marker) {
    _hasSelected.value = marker != _hasSelected.value ? marker : null;
  }


  void deleteSelection() {
    if (_hasSelected.value == null) {
      return;
    }

    int index = _hasSelected.value!.index;
    _pdfMarkers.removeWhere((item) => item == _hasSelected.value);
    _selections.remove(index);
    _hasSelected.value = null;
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
    var markers = _pdfMarkers.where((marker) => marker.pageNumber == page.pageNumber);
    if (markers.isEmpty) return;
    
    for (PdfMarker marker in markers) {
      final paint = Paint()
        ..color = marker == _hasSelected.value ? const ui.Color.fromARGB(255, 20, 115, 112).withAlpha(70) : marker.color
        ..style = PaintingStyle.fill;

      final documentRect = _pdfRectToRectInDocument(
        marker.bounds, 
        page: page, 
        pageRect: pageRect
      );

      canvas.drawRect(documentRect, paint);
  // Handles text extraction with image extract opportunity
  Future<void> _handleSelection(Rect selRect) async {
    if (!_controller.isReady) {
      _showError('PDF controller not ready');
      return;
    }

    final topLeft = _controller.getPdfPageHitTestResult(selRect.topLeft, useDocumentLayoutCoordinates: false);
    final bottomRight = _controller.getPdfPageHitTestResult(selRect.bottomRight, useDocumentLayoutCoordinates: false);

    if (topLeft == null || bottomRight == null || topLeft.page != bottomRight.page) {
      _showError('Invalid selection area');
      return;
    }

    final pdfRect = PdfRect(topLeft.offset.x, topLeft.offset.y, bottomRight.offset.x, bottomRight.offset.y);
    
    _pendingSelectionData = {
      'pdfRect': pdfRect,
      'page': topLeft.page,
      'selRect': selRect,
    };

    try {
      final pageText = await topLeft.page.loadStructuredText();
      final fragments = pageText.fragments.where((frag) => pdfRect.overlaps(frag.bounds)).toList();
      final selectedText = fragments.map((f) => f.text).join('');
      
      if (fragments.isNotEmpty) {
        _pendingSelection = TextSelection(
          text: selectedText,
          bounds: pdfRect,
          pageNumber: topLeft.page.pageNumber,
          globalRect: _getGlobalRect(selRect),
          label: 'Selection ${_selections.length + 1}',
          language: 'Undefined'
        );
      }
    } catch (e) {
      // Continue for image extraction even if text loading fails
    }
  }
  
  // Handles image extraction
  void _handleImageExtraction() async {
    if (_pendingSelectionData == null) {
      _showError('No selection data available for image extraction');
      return;
    }

    _clearOverlays();
    await _extractImageFromSelection(
      _pendingSelectionData!['pdfRect'] as PdfRect,
      _pendingSelectionData!['page'] as PdfPage,
    );
  }
  
  // Clear a selection
  void _clearSelection() {
    _clearOverlays();
    _pendingSelection = null;
    _pendingImageData = null;
    _pendingSelectionData = null;
  }

  // Clear all selections
  void _clearAllSelections() {
    _selections.clear();
    _pdfMarkers.clear();
    _imageAnnotations.clear();
  }

  // ==================================================
  // === OVERLAY MANAGEMENT & COORDINATE CONVERSION ===
  // ==================================================

  // Shows selection box and label popup
  void _updateSelectionOverlay(Rect localRect, bool end) {
    _clearOverlays();

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
              color: const ui.Color.fromARGB(108, 180, 146, 242),
              border: Border.all(color: const ui.Color.fromARGB(255, 129, 95, 244), width: 2),
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
          child: _buildDualLabelButton(),
        ),
      );
      Overlay.of(context).insert(_entryLabel!);
    }
  }

  // Clear all overlays
  void _clearOverlays() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
  }

  // Convert Flutter widget rect -> Global screen rect
  Rect _getGlobalRect(Rect localRect) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    return Rect.fromPoints(
      renderBox.localToGlobal(localRect.topLeft),
      renderBox.localToGlobal(localRect.bottomRight),
    );
  }
  
  // Convert PDF rect -> Flutter widget rect
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

  // =====================================
  // === UI BUILDING METHODS & DIALOGS ===
  // =====================================

  // Build label box for text + images
  Widget _buildDualLabelButton() {
    return Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: const ui.Color.fromARGB(255, 180, 176, 190),
        borderRadius: BorderRadius.circular(4.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLabelOptionButton(
            'Text',
            Icons.text_fields,
            const ui.Color.fromARGB(255, 1, 219, 223),
            () => _showTextLabelDialog(_pendingSelection!),
          ),
          const SizedBox(width: 8),
          _buildLabelOptionButton(
            'Image',
            Icons.image,
            const ui.Color.fromARGB(255, 61, 196, 66),
            _handleImageExtraction,
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

  // Builds the options for the selection label
  Widget _buildLabelOptionButton(String text, IconData icon, Color color, VoidCallback onPressed) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Creates text rendering objects
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

  // Text label information
  void _showTextLabelDialog(TextSelection selection) {
    const List<String> labels = ['Title', 'Caption', 'Paragraph', 'Author'];
    const List<String> languages = ['English', 'Not English', 'Other'];
    String dropdownLabel = 'Title';
    String dropdownLanguage = 'English';

    _clearOverlays();

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
                  const Text('Category:'),
                  DropdownButton<String>(
                    value: dropdownLabel,
                    isExpanded: true,
                    items: labels.map((String label) {
                      return DropdownMenuItem(value: label, child: Text(label));
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateDialog(() => dropdownLabel = newValue!);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Language:'),
                  DropdownButton<String>(
                    value: dropdownLanguage,
                    isExpanded: true,
                    items: languages.map((String language) {
                      return DropdownMenuItem(value: language, child: Text(language));
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateDialog(() => dropdownLanguage = newValue!);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();

                    _updateSelectionLabel(selection, dropdownlabel);
                    _finalizeTextSelection(selection, dropdownLabel, dropdownLanguage);
                    _indexCount++;
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
  
  // Image label information 
  void _showImageLabelDialog() {
    const List<String> imageTypes = ['Figure', 'Diagram', 'Photo', 'Drawing', 'Other'];
    String selectedImageType = 'Figure';
    String imageLabel = 'Image ${_imageAnnotations.length + 1}';

    _clearOverlays();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Label Image'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Image Type:'),
                  DropdownButton<String>(
                    value: selectedImageType,
                    isExpanded: true,
                    items: imageTypes.map((String type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateDialog(() => selectedImageType = newValue!);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Custom Label:'),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Enter a custom label...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setStateDialog(() {
                        imageLabel = value.isNotEmpty ? value : selectedImageType;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _clearSelection();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _finalizeImage(selectedImageType, imageLabel);
                  },
                  child: const Text('Save Image'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // ===============================
  // === TEXT & IMAGE PROCESSING ===
  // ===============================

  // Adds the text selection + marker
  void _finalizeTextSelection(TextSelection selection, String newLabel, String language) {
    _clearOverlays();

    final newMarker = PdfMarker(
      color: const ui.Color.fromARGB(255, 103, 243, 239).withAlpha(100),
      bounds: selection.bounds,
      pageNumber: selection.pageNumber,
      text: newLabel,
      index: _indexCount,
    );
    
    _pdfMarkers.add(newMarker);
    
    final updatedSelection = selection.copyWith(label: newLabel, language: language);
    _selections.add(updatedSelection);
    
    _pendingSelection = null;
    _pendingSelectionData = null;
    
    _safeSetState(() {});
  }

      
  // Update/add the label of a specific selection
  void _updateSelectionLabel(TextSelection selection, String newLabel) {
    _selections.update(_indexCount, (value) => selection.copyWith(label: newLabel.isEmpty ? 'Unlabeled' : newLabel), ifAbsent: () => selection.copyWith(label: newLabel.isEmpty ? 'Unlabeled' : newLabel));
    debugPrint('All Selections:');
    for (final s in _selections.values) {
      debugPrint('Label: ${s.label}, Text: ${s.text}');
    }
  }

  // Extract the actual image
  Future<void> _extractImageFromSelection(PdfRect pdfRect, PdfPage page) async {
    if (pdfRect.width <= 0 || pdfRect.height <= 0) {
      _showError('Invalid selection area - please select a larger area');
      return;
    }

    try {
      final pdfHeight = page.height;
      final flippedY = pdfHeight - (pdfRect.bottom + pdfRect.height);
      
      final image = await page.render(
        x: pdfRect.left.toInt(),
        y: flippedY.toInt(),
        width: pdfRect.width.toInt(),
        height: pdfRect.height.toInt(),
      );
      
      if (image?.pixels == null || image!.pixels.isEmpty) {
        _showError('No image data found in selected area');
        return;
      }

      final pngBytes = await _encodeImageToPng(image.pixels, pdfRect.width.toInt(), pdfRect.height.toInt());
      
      if (pngBytes != null) {
        _pendingImageData = {
          'pixels': pngBytes,
          'pdfRect': pdfRect,
          'pageNumber': page.pageNumber,
        };
        _showImageLabelDialog();
      }
    } catch (e) {
      _showError('Error extracting image: $e');
    }
  }

  // Create PNG from raw pixels
  Future<Uint8List?> _encodeImageToPng(Uint8List bgraPixels, int width, int height) async {
    try {
      final rgbaPixels = _convertBgraToRgba(bgraPixels);
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaPixels.buffer,
        numChannels: 4,
      );
      final pngBytes = img.encodePng(image);
      return Uint8List.fromList(pngBytes);
    } catch (e) {
      _showError('Error encoding PNG: $e');
      return null;
    }
  }

  // Take pdfrx BGRA -> RGBA for png
  Uint8List _convertBgraToRgba(Uint8List bgraPixels) {
    final rgbaPixels = Uint8List(bgraPixels.length);
    for (int i = 0; i < bgraPixels.length; i += 4) {
      rgbaPixels[i] = bgraPixels[i + 2];     // R
      rgbaPixels[i + 1] = bgraPixels[i + 1]; // G
      rgbaPixels[i + 2] = bgraPixels[i];     // B
      rgbaPixels[i + 3] = bgraPixels[i + 3]; // A
    }
    return rgbaPixels;
  }

  // Add image item 
  void _finalizeImage(String imageType, String label) async {
    if (_pendingImageData == null) return;

    final pixels = _pendingImageData!['pixels'] as Uint8List;
    final pdfRect = _pendingImageData!['pdfRect'] as PdfRect;
    final pageNumber = _pendingImageData!['pageNumber'] as int;
    
    final timestamp = DateTime.now();
    final fileName = '${imageType.toLowerCase()}_page${pageNumber}_${label}_$timestamp.png';
    
    await _saveImageToFile(pixels, fileName);
    
    for (int i = 0; i < maxLength; i++) {
      text.writeln('\nITEM ${i + 1}:');
      text.writeln('-' * 30);
      
      // Add selections
      for (TextSelection s in _selections.values) {
        text.writeln('SELECTION:');
        text.writeln('  Label: ${s.label}');
        text.writeln('  Page: ${s.pageNumber}');
        text.writeln('  Text: "${s.text}"');
        text.writeln('  Position: (${s.bounds.left}, ${s.bounds.top}) to (${s.bounds.right}, ${s.bounds.bottom})');
      }
    _imageAnnotations.add(ImageAnnotation(
      imageBytes: pixels,
      imageName: fileName,
      bounds: pdfRect,
      pageNumber: pageNumber,
      label: '$imageType: $label',
    ));
    
    _pendingImageData = null;
    _pendingSelectionData = null;
    
    _showSnackBar('$imageType saved: $label');
    _clearOverlays();
    _safeSetState(() {});
  }

  // ==================================
  // === PAINT TEXT & IMAGE MARKERS ===
  // ==================================

  // Shows text selection overlays
  void _paintTextMarkers(Canvas canvas, Rect pageRect, PdfPage page) {
    final markers = _pdfMarkers.where((marker) => marker.pageNumber == page.pageNumber).toList();
    if (markers.isEmpty) return;
    
    for (final marker in markers) {
      final paint = Paint()
        ..color = marker.color
        ..style = PaintingStyle.fill;

      final documentRect = _pdfRectToRectInDocument(marker.bounds, page: page, pageRect: pageRect);
      canvas.drawRect(documentRect, paint);

      final paragraph = _buildParagraph(marker.text, documentRect.width, fontSize: 10, color: Colors.black);
      canvas.drawParagraph(paragraph, Offset(documentRect.left + 3, documentRect.top - 12));
    }
  }

  // Shows image selection overlays
  void _paintImages(Canvas canvas, Rect pageRect, PdfPage page) {
    final images = _imageAnnotations.where((img) => img.pageNumber == page.pageNumber).toList();
    if (images.isEmpty) return;
    
    for (final imageAnnotation in images) {
      final documentRect = _pdfRectToRectInDocument(imageAnnotation.bounds, page: page, pageRect: pageRect);
      
      final paint = Paint()
        ..color = const ui.Color.fromARGB(255, 107, 240, 136).withAlpha(100)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(documentRect, paint);
      
      final paragraph = _buildParagraph(
        imageAnnotation.label, 
        documentRect.width, 
        fontSize: 10, 
        color: const ui.Color.fromARGB(255, 0, 0, 0)
      );
      canvas.drawParagraph(paragraph, Offset(documentRect.left + 3, documentRect.top - 12));
    }
  }

  // ========================
  // === FILE & EXPORTING ===
  // ========================

  // Saves the image locally
  Future<void> _saveImageToFile(Uint8List imageBytes, String fileName) async {
    try {
      final location = await fs.getSaveLocation(suggestedName: fileName);
      if (location != null) {
        final file = fs.XFile.fromData(imageBytes, mimeType: 'image/png', name: fileName);
        await file.saveTo(location.path);
        _showSnackBar('Image saved as: $fileName');
      }
    } catch (e) {
      _showError('Failed to save image: $e');
    }
  }
  
  // Saves the data .txt file to downloads
  Future<void> _saveTextToFile(String text) async {
    final location = await fs.getSaveLocation(suggestedName: 'pdf_annotations.txt');
    if (location != null) {
      final file = fs.XFile.fromData(
        Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
        name: 'pdf_annotations.txt',
      );
      await file.saveTo(location.path);
    }
  }

  void _handleExportTrigger() {
    if (widget.exportTrigger?.value == true) {
      exportPairedToText();
      widget.exportTrigger?.value = false;
    }
  }

  // Creates the file of data to export
  Future<void> exportPairedToText() async {
    final text = StringBuffer();
    
    text.writeln('PDF EXTRACTIONS');
    text.writeln('=' * 50);
    
    for (int i = 0; i < _selections.length; i++) {
      final s = _selections[i];
      text.writeln('\nTEXT EXTRACTION ${i + 1}:');
      text.writeln('-' * 30);
      text.writeln('  Label: ${s.label}');
      text.writeln('  Language: ${s.language}'); 
      text.writeln('  Page: ${s.pageNumber}');
      text.writeln('  Text: "${s.text}"');
      text.writeln('  Position: (${s.bounds.left}, ${s.bounds.top}) to (${s.bounds.right}, ${s.bounds.bottom})');
    }
    
    if (_imageAnnotations.isNotEmpty) {
      text.writeln('\n\nIMAGE EXTRACTIONS');
      text.writeln('=' * 50);
      
      for (int i = 0; i < _imageAnnotations.length; i++) {
        final img = _imageAnnotations[i];
        text.writeln('\nIMAGE ${i + 1}:');
        text.writeln('  Name: ${img.imageName}');
        text.writeln('  Label: ${img.label}');
        text.writeln('  Page: ${img.pageNumber}');
        text.writeln('  Position: (${img.bounds.left}, ${img.bounds.top}) to (${img.bounds.right}, ${img.bounds.bottom})');
        text.writeln('  Size: ${img.imageBytes.length} bytes');
      }
    }
    
    await _saveTextToFile(text.toString());
  }

  // ============================
  // === ERROR HELPER METHODS ===
  // ============================

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

}

// Text, Markers & Images classes
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

class PdfMarker {
  Color color;
  final PdfRect bounds;
  final int pageNumber;
  final String text;
  final int index;

  PdfMarker({
    required this.color,
    required this.bounds,
    required this.pageNumber,
    required this.text,
    required this.index,
  });
}

class ImageAnnotation {
  final Uint8List imageBytes;
  final String imageName;
  final PdfRect bounds;
  final int pageNumber;
  final String label;

  ImageAnnotation({
    required this.imageBytes,
    required this.imageName,
    required this.bounds,
    required this.pageNumber,
    required this.label,
  });
}