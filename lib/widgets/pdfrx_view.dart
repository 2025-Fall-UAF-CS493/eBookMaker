import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image/image.dart' as img;
import 'package:customizable_dropdown_menu/customizable_dropdown_menu.dart';

// Dropdown Options
const List<String> TEIlabels = ['Title', 'Caption', 'Paragraph', 'Author'];
const List<String> TEIlanguages = ['English', 'Not English', 'Other'];
const List<String> imageTypes = ['Figure', 'Diagram', 'Photo', 'Drawing', 'Other'];

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

  // Data collections
  final Map<int, TextSelection> _selections = {};
  final List<PdfMarker> _pdfMarkers = [];
  final List<ImageAnnotation> _imageAnnotations = [];

  // Sidebar variables
  final _markerSelect = ValueNotifier<PdfMarker?>(null);
  final _sidebarEdit = ValueNotifier<bool>(false);
  String _sidebarLabel = "";
  String _sidebarLang = "";
  final TextEditingController _sidebarText = TextEditingController(text: "");
  
  final _imageSelect = ValueNotifier<ImageAnnotation?>(null);
  final TextEditingController _sidebarImageLabel = TextEditingController(text: "");
  final TextEditingController _sidebarImageName = TextEditingController(text: "");


  // Shared index corresponding selections and markers
  int _indexCount = 0;

  // Pending operations
  TextSelection? _pendingSelection;
  Map<String, dynamic>? _pendingSelectionData;
  Map<String, dynamic>? _pendingImageData;

  // =========================
  // === LIFECYCLE METHODS ===
  // =========================

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

  void openSidebar(PdfMarker? marker, ImageAnnotation? img) {
    _sidebarEdit.value = false;
    if (marker != null) {
      _markerSelect.value = marker;
      _sidebarLabel = marker.label;
      _sidebarLang = _selections[marker.index]!.language;
      _sidebarText.text = _selections[marker.index]!.text;

    } else if (img != null) {
      _imageSelect.value = img;
      _sidebarImageLabel.text = img.type;
      _sidebarImageName.text = img.name;
    }
  }

  void closeSidebar() {
    _sidebarEdit.value = false;
    _sidebarLabel = "";
    _sidebarLang = "";
    _sidebarText.text = "";
    _markerSelect.value = null;

    _sidebarImageLabel.text = "";
    _sidebarImageName.text = "";
    _imageSelect.value = null;

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
                    pagePaintCallbacks: [_paintTextMarkers, _paintImages],
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,

                    onTapDown: (details) async {
                      final pdfTap = _controller.getPdfPageHitTestResult(
                        details.localPosition,
                        useDocumentLayoutCoordinates: false,
                      );

                      // Check for hit on a TextSelection
                      for (PdfMarker marker in _pdfMarkers) {
                        if (pdfTap != null && marker.bounds.containsPoint(pdfTap.offset)) {
                          if(marker != _markerSelect.value) {
                            openSidebar(marker, null);
                          } else {
                            closeSidebar();
                          }
                          return;
                        }
                      }
                      // Check for hit on an ImageSelection
                      for (ImageAnnotation img in _imageAnnotations) {
                        if (pdfTap != null && img.bounds.containsPoint(pdfTap.offset)) {
                          if (img != _imageSelect.value) {
                            openSidebar(null, img);
                          } else {
                            closeSidebar();
                          }
                          return;
                        }
                      }
                      if (pdfTap != null) {
                        closeSidebar();
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
                      _dragStart = null;
                      _dragCurrent = null;
                    },
                    onDoubleTap: _clearSelection,
                  ),
                ),
              ],
            ),
          ),

          // Sidebar
          ValueListenableBuilder<PdfMarker?>(
            valueListenable: _markerSelect,
            builder: (_, marker, _) {

              return ValueListenableBuilder<ImageAnnotation?>(
                valueListenable: _imageSelect,
                builder: (_, image, _) {

                  final visible = marker != null || image != null;
                  final isImage = image != null;

                  return visible ? SizedBox(
                    width: 250,
                    child: ValueListenableBuilder(
                      valueListenable: _sidebarEdit,
                      builder: (_, editMode, _) {
                        return Column (
                          children: [
                            Spacer(flex: 1),
                        
                            // Text Selection Display
                            !isImage ?
                            Expanded(
                              flex: 6,
                              child: Column(
                                children: [
                                  Text("Text"),
                                  Expanded(
                                    flex: 8,
                                    child: Card(
                                      child: SingleChildScrollView(
                                        child: Padding(
                                          padding: const EdgeInsets.all(15.0),
                                          child: editMode ? 
                                            TextField(
                                              controller: _sidebarText,
                                              onChanged: (String? newValue) {
                                                _sidebarText.text = newValue!;
                                              },
                                              maxLines: null,
                                            )
                                            :
                                            Text( _selections[marker!.index]!.text)
                                        ),
                                      )
                                    )
                                  ),
                              
                                  Spacer(),
                              
                                  Text("Label"),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(10.0),
                                        child: !editMode
                                        ?
                                        Text(marker!.label)
                                        :
                                        StatefulBuilder(
                                          builder: (context, dropDownState) {
                                          return DropdownButton<String>(
                                              value: _sidebarLabel,
                                              isExpanded: true,
                                              items: TEIlabels.map((String label) {
                                                return DropdownMenuItem(value: label, child: Text(label));
                                              }).toList(),
                                              onChanged: (String? newValue) {
                                                dropDownState(() => _sidebarLabel = newValue!);
                                              },
                                            );
                                          }
                                        )
                                      ),
                                    )
                                  ),
                              
                                  Spacer(),
                              
                                  Text("Language"),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(10.0),
                                        child: !editMode
                                        ?
                                        Text(_selections[marker!.index]!.language)
                                        :
                                        StatefulBuilder(
                                          builder: (context, dropDownState) {
                                          return DropdownButton<String>(
                                              value: _sidebarLang,
                                              isExpanded: true,
                                              items: TEIlanguages.map((String label) {
                                                return DropdownMenuItem(value: label, child: Text(label));
                                              }).toList(),
                                              onChanged: (String? newValue) {
                                                dropDownState(() => _sidebarLang = newValue!);
                                              },
                                            );
                                          }
                                        )
                                      ),
                                    )
                                  ),
                                ],
                              ),
                            )
                            :
                            // Image Display
                            Expanded(
                              flex: 4,
                              child: Column (
                                children: [
                                  Text("Label"),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(10.0),
                                        child: !editMode
                                        ?
                                        Text(image.type)
                                        :
                                        StatefulBuilder(
                                          builder: (context, dropDownState) {
                                          return CustomizableDropDown(
                                              textController: _sidebarImageLabel,
                                              multiselect: false,
                                              selectedItems: [],
                                              items: imageTypes,
                                              onSelectionChange: (selectedItems) {
                                                dropDownState(() => _sidebarImageLabel.text = selectedItems[0]);
                                              },
                                            );
                                          }
                                        )
                                      ),
                                    )
                                  ),
                              
                                  Spacer(),
                              
                                  Text("Name"),
                                  Expanded(
                                    child: Card(
                                      child: SingleChildScrollView(
                                        child: Padding(
                                          padding: const EdgeInsets.all(15.0),
                                          child: editMode ? 
                                            TextField(
                                              controller: _sidebarImageName,
                                              onChanged: (String? newValue) {
                                                _sidebarImageName.text = newValue!;
                                              },
                                            )
                                            :
                                            Text(image.name)
                                        ),
                                      )
                                    )
                                  ),
                              
                                ],
                              ),
                            ),
                            
                        
                            Spacer(flex: 1),
                        
                            editMode ?
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(255, 135, 209, 230),
                                    ),
                                    icon: const Icon(Icons.highlight_off_rounded, size: 18),
                                    label: const Text("Cancel"),
                                    onPressed: () => { 
                                      isImage ?
                                      openSidebar(null, image)
                                      :
                                      openSidebar(marker, null)
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(255, 35, 97, 146),
                                    ),
                                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                                    label: const Text("Save"),
                                    onPressed: isImage ?
                                      () => updateImageSelection(image, _sidebarImageLabel.text, _sidebarImageName.text)
                                      :
                                      () => updateTextSelection(marker!, _sidebarText.text, _sidebarLabel, _sidebarLang),
                                  )
                                ],
                              ),
                            )
                            :
                            Center(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Color.fromARGB(255, 35, 97, 146),
                                ),
                                icon: const Icon(Icons.border_color_rounded, size: 18),
                                label: const Text("Edit"),
                                onPressed: () => _sidebarEdit.value = !_sidebarEdit.value,
                              )
                            ),
                        
                            Spacer(flex: 1),
                        
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
                        );
                      }
                    )
                  )
                  : Text("");
                }
              );
            }
          )
        ],
      ),
    );
  }
  
  // ==========================
  // === SELECTION HANDLING ===
  // ==========================

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

  // Update a TextSelection/marker from the sidebar
  void updateTextSelection(PdfMarker marker, String text, String label, String lang) {
    PdfMarker m = _pdfMarkers.firstWhere((m) => m == marker);
    m.label = label;
    TextSelection t = _selections[m.index]!;
    t.label = label;
    t.language = lang;
    t.text = text;

    closeSidebar();
  }

  // Update an ImageAnnotation from the sidebar
  void updateImageSelection(ImageAnnotation img, String label, String name) {
    ImageAnnotation i = _imageAnnotations.firstWhere((i) => i == img);
    i.type = label;
    i.name = name;

    closeSidebar();
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
    _markerSelect.value = null;
    _selections.clear();
    _pdfMarkers.clear();
    _imageAnnotations.clear();
  }


  void deleteSelection() {
    if (_markerSelect.value != null) {
      print("Deleting text marker...");
      int index = _markerSelect.value!.index;
      _pdfMarkers.removeWhere((item) => item == _markerSelect.value);
      _selections.remove(index);
      _markerSelect.value = null;

    } else if (_imageSelect.value != null) {
      print("Deleting image annotation...");
      _imageAnnotations.removeWhere((item) => item == _imageSelect.value);
      _imageSelect.value = null;
    }
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
              color: const ui.Color.fromARGB(100, 135, 209, 230),
              border: Border.all(color: const ui.Color.fromARGB(255, 135, 209, 230), width: 2),
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
        color: const ui.Color.fromARGB(255, 196, 207, 218),
        borderRadius: BorderRadius.circular(4.0)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLabelOptionButton(
            'Text',
            Icons.text_fields_rounded,
            const ui.Color.fromARGB(255, 35, 97, 146),
            () => _showTextLabelDialog(_pendingSelection!),
          ),
          const SizedBox(width: 8),
          _buildLabelOptionButton(
            'Image',
            Icons.image,
            const ui.Color.fromARGB(255, 255, 205, 0),
            _handleImageExtraction,
            textColor: Color.fromARGB(255, 17, 28, 78),
            iconColor: Color.fromARGB(255, 17, 28, 78)
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, color: Color.fromARGB(255, 17, 28, 78)),
            onPressed: _clearSelection,
          ),
        ],
      ),
    );
  }

  // Builds the options for the selection label
  Widget _buildLabelOptionButton(String text, IconData icon, Color color, VoidCallback onPressed, 
                            {Color iconColor = Colors.white, Color textColor = Colors.white}) {
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
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
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
    TextEditingController dropdownLabel = TextEditingController(text: 'Title');
    TextEditingController dropdownLanguage = TextEditingController(text: 'English');

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
                  CustomizableDropDown(
                    textController: dropdownLabel,
                    items: TEIlabels,
                    multiselect: false,
                    selectedItems: [],
                    onSelectionChange: (newValue) {
                      setStateDialog(() => dropdownLabel.text = newValue[0]);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Language:'),
                  CustomizableDropDown(
                    textController: dropdownLanguage,
                    multiselect: false,
                    selectedItems: [],
                    items: TEIlanguages,
                    onSelectionChange: (newValue) {
                      setStateDialog(() => dropdownLanguage.text = newValue[0]);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _finalizeTextSelection(selection, dropdownLabel.text, dropdownLanguage.text);
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
    TextEditingController selectedImageType = TextEditingController(text: 'Figure');
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
                  CustomizableDropDown(
                    textController: selectedImageType,
                    selectedItems: [],
                    multiselect: false,
                    items: imageTypes,
                    onSelectionChange: (newValue) {
                      setStateDialog(() => selectedImageType.text = newValue[0]);
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
                        imageLabel = value.isNotEmpty ? value : selectedImageType.text;
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
                    _finalizeImage(selectedImageType.text, imageLabel);
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
      color: const ui.Color.fromARGB(255, 135, 209, 230).withAlpha(100),
      bounds: selection.bounds,
      pageNumber: selection.pageNumber,
      label: newLabel,
      index: _indexCount,
    );
    
    _pdfMarkers.add(newMarker);
    
    final updatedSelection = selection.copyWith(label: newLabel, language: language);
    _selections.update(_indexCount, (value) => updatedSelection, ifAbsent: () => updatedSelection);

    _indexCount++;
    
    _pendingSelection = null;
    _pendingSelectionData = null;
    
    _safeSetState(() {});
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
    
    _imageAnnotations.add(ImageAnnotation(
      imageBytes: pixels,
      fileName: fileName,
      bounds: pdfRect,
      pageNumber: pageNumber,
      type: imageType,
      name: label,
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
        ..color = marker == _markerSelect.value ? const ui.Color.fromARGB(255, 135, 209, 230).withAlpha(70) : marker.color
        ..style = PaintingStyle.fill;

      final documentRect = _pdfRectToRectInDocument(marker.bounds, page: page, pageRect: pageRect);
      canvas.drawRect(documentRect, paint);

      final paragraph = _buildParagraph(marker.label, documentRect.width, fontSize: 10, color: Colors.black);
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
        ..color = const ui.Color.fromARGB(255, 255, 205, 0).withAlpha(100)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(documentRect, paint);
      
      final paragraph = _buildParagraph(
        '${imageAnnotation.type}: ${imageAnnotation.name}', 
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
  
  // Saves the data .xml file to downloads
  Future<void> _saveTextToFile(String text) async {
    final location = await fs.getSaveLocation(suggestedName: 'pdf_annotations.xml');
    if (location != null) {
      final file = fs.XFile.fromData(
        Uint8List.fromList(utf8.encode(text)),
        mimeType: 'application/xml',
        name: 'pdf_annotations.xml',
      );
      await file.saveTo(location.path);
    }
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  void _handleExportTrigger() {
    if (widget.exportTrigger?.value == true) {
      exportPairedToText();
      widget.exportTrigger?.value = false;
    }
  }

  // Creates the file of data to export as XML
  Future<void> exportPairedToText() async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<pdfExtractions>');

    xml.writeln('  <textExtractions>');
    int i = 1;
    for (TextSelection s in _selections.values) {
      xml.writeln('    <textExtraction index="$i">');
      xml.writeln('      <label>${_escapeXml(s.label)}</label>');
      xml.writeln('      <language>${_escapeXml(s.language)}</language>');
      xml.writeln('      <page>${s.pageNumber}</page>');
      xml.writeln('      <text>${_escapeXml(s.text)}</text>');
      xml.writeln(
        '      <bounds left="${s.bounds.left}" top="${s.bounds.top}" right="${s.bounds.right}" bottom="${s.bounds.bottom}" />'
      );
      xml.writeln('    </textExtraction>');
      i++;
    }
    xml.writeln('  </textExtractions>');

    xml.writeln('  <imageExtractions>');
    for (int j = 0; j < _imageAnnotations.length; j++) {
      final img = _imageAnnotations[j];
      xml.writeln('    <imageExtraction index="${j + 1}">');
      xml.writeln('      <file>${_escapeXml(img.fileName)}</file>');
      xml.writeln('      <type>${_escapeXml(img.type)}</type>');
      xml.writeln('      <name>${_escapeXml(img.name)}</name>');
      xml.writeln('      <page>${img.pageNumber}</page>');
      xml.writeln(
        '      <bounds left="${img.bounds.left}" top="${img.bounds.top}" right="${img.bounds.right}" bottom="${img.bounds.bottom}" />'
      );
      xml.writeln('      <sizeBytes>${img.imageBytes.length}</sizeBytes>');
      xml.writeln('    </imageExtraction>');
    }
    xml.writeln('  </imageExtractions>');

    xml.writeln('</pdfExtractions>');

    await _saveTextToFile(xml.toString());
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
  String text;
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
  final Color color;
  final PdfRect bounds;
  final int pageNumber;
  String label;
  final int index;

  PdfMarker({
    required this.color,
    required this.bounds,
    required this.pageNumber,
    required this.label,
    required this.index,
  });
}

class ImageAnnotation {
  final Uint8List imageBytes;
  final String fileName;
  final PdfRect bounds;
  final int pageNumber;
  String type;
  String name;

  ImageAnnotation({
    required this.imageBytes,
    required this.fileName,
    required this.bounds,
    required this.pageNumber,
    required this.type,
    required this.name,
  });
}