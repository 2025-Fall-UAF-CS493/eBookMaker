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
  final PdfViewerController _controller = PdfViewerController();
  bool get selectMode => widget.selectModeNotifier.value;

  Offset? _dragStart;
  Offset? _dragCurrent;
  OverlayEntry? _selectionOverlay;
  OverlayEntry? _entryLabel;
  final List<TextSelection> _selections = [];
  // List to store all marker/highlight boxes with their data
  final List<PdfMarker> _pdfMarkers = [];
  final List<ImageAnnotation> _imageAnnotations = [];

  // Track the most recent selection for labeling
  TextSelection? _pendingSelection;
  Map<String, dynamic>? _pendingImageData;

  @override
  void initState() {
    super.initState();
    // Listen for triggers
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
              pagePaintCallbacks: [_paintMarkers, _paintImages],
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

  void _paintImages(Canvas canvas, Rect pageRect, PdfPage page) {
    final images = _imageAnnotations.where((img) => img.pageNumber == page.pageNumber).toList();
    if (images.isEmpty) return;
    
    for (final imageAnnotation in images) {
      final documentRect = _pdfRectToRectInDocument(
        imageAnnotation.bounds, 
        page: page, 
        pageRect: pageRect
      );
      
      // Draw a placeholder rectangle for now
      final paint = Paint()
        ..color = Colors.blue.withAlpha(100)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(documentRect, paint);
      
      // Draw image label
      final paragraph = _buildParagraph(
        imageAnnotation.label, 
        documentRect.width, 
        fontSize: 10, 
        color: Colors.blue
      );
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

  // Build the dual label button widget (Text + Image)
  Widget _buildDualLabelButton() {
    return Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 113, 201, 250),
        borderRadius: BorderRadius.circular(4.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Text label button
          _buildLabelOptionButton(
            'Text',
            Icons.text_fields,
            Colors.blue,
            () => _showTextLabelDialog(_pendingSelection!),
          ),
          const SizedBox(width: 8),
          // Image label button
          _buildLabelOptionButton(
            'Image',
            Icons.image,
            Colors.green,
            _handleImageExtraction,
          ),
          const SizedBox(width: 4),
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 16),
            onPressed: _clearSelection,
          ),
        ],
      ),
    );
  }

  // Build individual label option buttons
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

  void _updateSelectionOverlay(Rect localRect, bool end) {
    _safeRemoveOverlay(_selectionOverlay);
    _safeRemoveOverlay(_entryLabel);

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
          child: _buildDualLabelButton(),
        ),
      );
      Overlay.of(context).insert(_entryLabel!);
    } else {
      _entryLabel = null;
    }
  }

  Future<void> _handleSelection(Rect selRect) async {
    if (_controller.isReady) {
      debugPrint('=== SELECTION HANDLING STARTED ===');
      debugPrint('Screen selection: ${selRect.topLeft} to ${selRect.bottomRight}');
      
      // Convert screen coordinates to PDF page coordinates
      final topLeft = _controller.getPdfPageHitTestResult(
        selRect.topLeft,
        useDocumentLayoutCoordinates: false,
      );
      final bottomRight = _controller.getPdfPageHitTestResult(
        selRect.bottomRight,
        useDocumentLayoutCoordinates: false,
      );

      debugPrint('TopLeft PDF result: ${topLeft != null ? "page ${topLeft.page.pageNumber} at ${topLeft.offset}" : "null"}');
      debugPrint('BottomRight PDF result: ${bottomRight != null ? "page ${bottomRight.page.pageNumber} at ${bottomRight.offset}" : "null"}');

      if (topLeft != null && bottomRight != null && topLeft.page == bottomRight.page) {
        // Create PDF rectangle from selection coordinates
        final pdfRect = PdfRect(
          topLeft.offset.x, 
          topLeft.offset.y,
          bottomRight.offset.x, 
          bottomRight.offset.y
        );

        debugPrint('Created PDF Rect: L=${pdfRect.left}, T=${pdfRect.top}, R=${pdfRect.right}, B=${pdfRect.bottom}');
        debugPrint('PDF Rect dimensions: ${pdfRect.width} x ${pdfRect.height}');

        // ALWAYS store selection data for potential image extraction
        _pendingSelectionData = {
          'pdfRect': pdfRect,
          'page': topLeft.page,
          'selRect': selRect,
        };

        debugPrint('Selection data stored for image extraction');

        // Try to extract text to see if there's any text content
        PdfPageText? pageText;
        try {
          pageText = await topLeft.page.loadStructuredText();
        } catch (e) {
          debugPrint('Failed to load page text: $e - but continuing for image extraction');
          // Don't return here - we still want to allow image extraction even if text loading fails
        }

        if (pageText != null) {
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
              language: 'Undefined' // Default language
            );
            
            // Set as pending selection to show label button
            _pendingSelection = newSelection;

            debugPrint('Text found in selection: $selectedText');
            debugPrint('Total selections: ${_selections.length+1}');
          } else {
            debugPrint('No text fragments found in selection area');
            // Still allow image extraction even if no text is found
            _pendingSelection = null;
          }
        } else {
          debugPrint('Page text is null - selection may contain only images');
          _pendingSelection = null;
        }
      } else {
        debugPrint('Invalid PDF hit test results - cannot extract');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid selection area')),
          );
        }
      }
    } else {
      debugPrint('PDF controller not ready');
    }
  }

  // Add this variable to store pending selection data
  Map<String, dynamic>? _pendingSelectionData;

  void _safeRemoveOverlay(OverlayEntry? overlay) {
    if (overlay != null) {
      overlay.remove();
    }
  }

  // Handle image extraction when image button is clicked
  void _handleImageExtraction() async {
    if (_pendingSelectionData != null) {
      final pdfRect = _pendingSelectionData!['pdfRect'] as PdfRect;
      final page = _pendingSelectionData!['page'] as PdfPage;
      
      debugPrint('=== IMAGE EXTRACTION STARTED ===');
      debugPrint('PDF Rect: ${pdfRect.left}, ${pdfRect.top}, ${pdfRect.width}, ${pdfRect.height}');
      debugPrint('Page: ${page.pageNumber}');
      
      // Remove the label overlay
      _entryLabel?.remove();
      _entryLabel = null;
      
      await _extractImageFromSelection(pdfRect, page);
    } else {
      debugPrint('No pending selection data for image extraction');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No selection data available for image extraction')),
        );
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

  // Show text label dialog (like in old file)
  void _showTextLabelDialog(TextSelection selection) {
    const List<String> labels = ['Title', 'Caption', 'Paragraph', 'Author'];
    String dropdownlabel = 'Title';
    const List<String> languages = ['English', 'Not English', 'Other'];
    String dropdownLanguage = 'English';

    // Remove overlays BEFORE showing dialog
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;

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
                    _finalizeTextSelection(selection, dropdownlabel, dropdownLanguage);
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

  void _finalizeTextSelection(TextSelection selection, String newLabel, String language) {
    // Safely remove overlays (they might already be null)
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;

    // This is a text selection - create marker
    final newMarker = PdfMarker(
      color: const Color.fromARGB(255, 45, 246, 239).withAlpha(70),
      bounds: selection.bounds,
      pageNumber: selection.pageNumber,
      text: newLabel
    );
    
    _pdfMarkers.add(newMarker);
    
    // Also update the selection with the label
    final updatedSelection = selection.copyWith(label: newLabel, language: language);
    _selections.add(updatedSelection);
    
    _pendingSelection = null;
    _pendingSelectionData = null;
    
    setState(() {}); // Refresh to show the new marker
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

// Add this method to convert BGRA to RGBA and encode to PNG
  Future<Uint8List?> _encodeImageToPng(Uint8List bgraPixels, int width, int height) async {
    try {
      debugPrint('Converting BGRA to PNG: ${bgraPixels.length} bytes, $width x $height');
      
      // Convert BGRA to RGBA
      final rgbaPixels = _convertBgraToRgba(bgraPixels);
      
      // Create an Image object from the converted RGBA pixel data
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgbaPixels.buffer,
        numChannels: 4, // RGBA
      );
      
      // Encode to PNG
      final pngBytes = img.encodePng(image);
      
      debugPrint('PNG encoded successfully: ${pngBytes.length} bytes');
      return Uint8List.fromList(pngBytes);
    } catch (e) {
      debugPrint('Error encoding PNG: $e');
      return null;
    }
  }

  // Convert BGRA to RGBA
  Uint8List _convertBgraToRgba(Uint8List bgraPixels) {
    // BGRA to RGBA conversion: swap Red and Blue channels
    final rgbaPixels = Uint8List(bgraPixels.length);
    
    for (int i = 0; i < bgraPixels.length; i += 4) {
      // BGRA: [Blue, Green, Red, Alpha]
      // RGBA: [Red, Green, Blue, Alpha]
      final blue = bgraPixels[i];      // B
      final green = bgraPixels[i + 1]; // G
      final red = bgraPixels[i + 2];   // R
      final alpha = bgraPixels[i + 3]; // A
      
      // Convert to RGBA
      rgbaPixels[i] = red;     // R
      rgbaPixels[i + 1] = green; // G
      rgbaPixels[i + 2] = blue;  // B
      rgbaPixels[i + 3] = alpha; // A
    }
    
    return rgbaPixels;
  }

  // Extract image from PDF using page rendering
  Future<void> _extractImageFromSelection(PdfRect pdfRect, PdfPage page) async {
    try {
      debugPrint('Starting image render...');
      
      // Ensure the selection area is valid
      if (pdfRect.width <= 0 || pdfRect.height <= 0) {
        debugPrint('Invalid selection area: ${pdfRect.width}x${pdfRect.height}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid selection area - please select a larger area')),
          );
          }
        return;
      }


      final pdfHeight = page.height;
      final flippedY = pdfHeight - (pdfRect.bottom + pdfRect.height);
      
      final width = (pdfRect.width).toInt();
      final height = (pdfRect.height).toInt();
      final x = pdfRect.left.toInt();
      final y = flippedY.toInt();
      
      final image = await page.render(
        x: x,
        y: y,
        width: width,
        height: height,
      );
      
      if (image != null) {
        debugPrint('Image rendered successfully');
        
        final pixels = image.pixels;
        
        if (pixels != null && pixels.isNotEmpty) {
          debugPrint('Image pixels extracted: ${pixels.length} bytes');
          
          final pngBytes = await _encodeImageToPng(pixels, width, height);
          
          if (pngBytes != null) {
            debugPrint('PNG encoded successfully: ${pngBytes.length} bytes');
            
            _pendingImageData = {
              'pixels': pngBytes,
              'pdfRect': pdfRect,
              'pageNumber': page.pageNumber,
            };
            
            _showImageLabelDialog();
          } else {
            debugPrint('Failed to encode PNG image');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to process image data')),
              );
            }
          }
        } else {
          debugPrint('No pixel data in rendered image');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No image data found in selected area')),
            );
          }
        }
      } else {
        debugPrint('Image render returned null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No image could be rendered from selected area')),
          );
        }
      }
      
    } catch (e, stackTrace) {
      debugPrint('Failed to extract image: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error extracting image: $e')),
        );
      }
    }
  }

  // Show image-specific label dialog
  void _showImageLabelDialog() {
    const List<String> imageTypes = ['Figure', 'Diagram', 'Chart', 'Photo', 'Screenshot', 'Other'];
    String selectedImageType = 'Figure';
    String imageLabel = 'Image ${_imageAnnotations.length + 1}';

    // Remove overlays before showing dialog
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;

    // Add image-specific label dialog
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
                  // Image type dropdown
                  const Text('Image Type:'),
                  DropdownButton<String>(
                    value: selectedImageType,
                    isExpanded: true,
                    items: imageTypes.map((String type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateDialog(() {
                        selectedImageType = newValue!;
                      });
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Custom label text field
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
                  
                  const SizedBox(height: 8),
                  
                  // Preview of the final label
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Final Label: $imageLabel',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _clearSelection(); // Cancel the selection
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


  Future<void> _saveImageToFile(Uint8List imageBytes, String fileName) async {
    try {
      final location = await fs.getSaveLocation(
        suggestedName: fileName,
      );
      
      if (location != null) {
        final file = fs.XFile.fromData(
          imageBytes,
          mimeType: 'image/png',
          name: fileName,
        );
        await file.saveTo(location.path);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Image saved as: $fileName')),
          );
        }
        debugPrint('Image saved to: ${location.path}');
      }
    } catch (e) {
      debugPrint('Failed to save image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save image: $e')),
        );
      }
    }
  }

  void _finalizeImage(String imageType, String label) async {
    if (_pendingImageData != null) {
      final pixels = _pendingImageData!['pixels'] as Uint8List;
      final pdfRect = _pendingImageData!['pdfRect'] as PdfRect;
      final pageNumber = _pendingImageData!['pageNumber'] as int;
      
      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${imageType.toLowerCase()}_page${pageNumber}_$timestamp.png';
      
      // Save the image to file
      await _saveImageToFile(pixels, fileName);
      
      // Create image annotation
      final imageAnnotation = ImageAnnotation(
        imageBytes: pixels,
        imageName: fileName,
        bounds: pdfRect,
        pageNumber: pageNumber,
        label: '$imageType: $label',
      );
      
      _imageAnnotations.add(imageAnnotation);
      
      // Clear pending data
      _pendingImageData = null;
      _pendingSelectionData = null;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$imageType saved: $label')),
        );
      }
      
      setState(() {});
    }
    
    // Clear any remaining overlays
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    _entryLabel?.remove();
    _entryLabel = null;
  }

  // Clear a selection
  void _clearSelection() {
    // Safely remove overlays using helper method
    _safeRemoveOverlay(_selectionOverlay);
    _selectionOverlay = null;
    _safeRemoveOverlay(_entryLabel);
    _entryLabel = null;
    
    if (_pendingSelection != null) {
      _pendingSelection = null;
    }
    
    // Clear pending data
    _pendingImageData = null;
    _pendingSelectionData = null;
    
    debugPrint('Selection cleared');
  }

  void _clearAllSelections(){
    _selections.clear();
    _pdfMarkers.clear();
    _imageAnnotations.clear();
  }

  Future<void> exportPairedToText() async {
    final text = StringBuffer();
    
    text.writeln('PDF EXTRACTIONS');
    text.writeln('=' * 50);
    
    // Text selections
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
    
    // Image extractions
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

// Data class for images and info
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