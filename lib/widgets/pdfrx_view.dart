// Main app interface, using pdfrx framework
// pdfrx tutorial/docs: https://github.com/espresso3389/pdfrx/tree/master/doc

// Allows user to make selections, classify them, export XML data,
// open PDF files, and access help functionality


import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image/image.dart' as img;

// Dropdown Options
const List<String> TEIlanguages = ['English', 'Akuzupik', 'Other'];

// Assigning colors
final Map<String, Color> TEIlabels = {
  'Title': Color.fromARGB(255, 0, 0, 255),       // Blue
  'Subtitle': Color.fromARGB(255, 2, 175, 206),  // Light Blue
  'Header': Color.fromARGB(255, 0, 128, 0),     // Green
  'Paragraph': Color.fromARGB(255, 255, 165, 0), // Orange
  'Author': Color.fromARGB(255, 128, 0, 128),    // Purple
};

class PDF extends StatefulWidget {
  final ValueNotifier<bool> selectModeNotifier;
  final PdfDocumentRef? documentRef;
  final ValueNotifier<bool>? exportTrigger; 
  final ValueNotifier<bool>? clearAllTrigger;

  const PDF({
    super.key, 
    required this.selectModeNotifier, 
    this.documentRef,
    this.exportTrigger,
    this.clearAllTrigger,
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
    widget.clearAllTrigger?.addListener(_handleClearAllTrigger);

  }

  @override
  void dispose() {
    widget.exportTrigger?.removeListener(_handleExportTrigger);
      widget.clearAllTrigger?.removeListener(_handleClearAllTrigger);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PDF oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.documentRef != oldWidget.documentRef) {
      _clearAllSelections();
    }
  }

  void _handleClearAllTrigger() {
    if (widget.clearAllTrigger?.value == true) {
      _clearAllSelections();
      closeSidebar();
      widget.clearAllTrigger?.value = false;
      _safeSetState(() {});
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
      _sidebarImageName.text = img.name;
    }
  }

  void closeSidebar() {
    _sidebarEdit.value = false;
    _sidebarLabel = "";
    _sidebarLang = "";
    _sidebarText.text = "";
    _markerSelect.value = null;

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

                  return visible ? Container(
                    width: 250,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Color.fromARGB(255, 35, 97, 146),
                          width: 3.0,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10.0),
                      child: ValueListenableBuilder(
                        valueListenable: _sidebarEdit,
                        builder: (_, editMode, __) {
                          return SingleChildScrollView(   
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // --- Close button ---
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.highlight_off_rounded,
                                          size: 20,
                                          color: Color.fromARGB(255, 17, 28, 78),
                                        ),
                                        onPressed: closeSidebar,
                                      ),
                                    ],
                                  ),
                                ),

                                SizedBox(height: 16),

                                // ===========================================================
                                // =============== TEXT SIDEBAR CONTENT ======================
                                // ===========================================================
                                if (!isImage)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Text",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      SizedBox(height: 8),
                                      Container(
                                        constraints: BoxConstraints(maxHeight: 120),
                                        child: Card(
                                          color: ui.Color.fromARGB(255, 184, 235, 249),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: editMode
                                                ? TextField(
                                                    controller: _sidebarText,
                                                    maxLines: null,
                                                  )
                                                : SingleChildScrollView(
                                                    child: Text(
                                                      _selections[marker!.index]!.text,
                                                      softWrap: true,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),

                                      SizedBox(height: 16),

                                      Text("Label",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 14)),
                                      Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Card(
                                          color: Color.fromARGB(255, 184, 235, 249),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: !editMode
                                                ? Text(marker!.label)
                                                : StatefulBuilder(builder:
                                                    (context, dropDownState) {
                                                    return DropdownButton<String>(
                                                      value: _sidebarLabel,
                                                      isExpanded: true,
                                                      items: TEIlabels.keys
                                                          .map((String label) =>
                                                              DropdownMenuItem(
                                                                  value: label,
                                                                  child: Text(label)))
                                                          .toList(),
                                                      onChanged: (String? newValue) {
                                                        dropDownState(() =>
                                                            _sidebarLabel = newValue!);
                                                      },
                                                    );
                                                  }),
                                          ),
                                        ),
                                      ),

                                      SizedBox(height: 16),

                                      Text("Language",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 14)),
                                      Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Card(
                                          color: Color.fromARGB(255, 184, 235, 249),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: !editMode
                                                ? Text(_selections[marker!.index]!.language)
                                                : StatefulBuilder(builder:
                                                    (context, dropDownState) {
                                                    return DropdownButton<String>(
                                                      value: _sidebarLang,
                                                      isExpanded: true,
                                                      items: TEIlanguages
                                                          .map(
                                                            (String lang) =>
                                                                DropdownMenuItem(
                                                                    value: lang,
                                                                    child: Text(lang)),
                                                          )
                                                          .toList(),
                                                      onChanged: (String? newValue) {
                                                        dropDownState(() =>
                                                            _sidebarLang = newValue!);
                                                      },
                                                    );
                                                  }),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                // ===========================================================
                                // ================ IMAGE SIDEBAR CONTENT ====================
                                // ===========================================================
                                if (isImage)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text("Name",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 14)),
                                      Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Card(
                                          color: Color.fromARGB(255, 184, 235, 249),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: editMode
                                                ? TextField(
                                                    controller: _sidebarImageName,
                                                  )
                                                : Text(image.name),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                SizedBox(height: 30),

                                // ===========================================================
                                // ===================== BUTTONS =============================
                                // ===========================================================

                                if (editMode)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              Color.fromARGB(255, 135, 209, 230),
                                        ),
                                        icon: Icon(Icons.highlight_off_rounded, size: 18),
                                        label: Text("Cancel"),
                                        onPressed: () => isImage
                                            ? openSidebar(null, image)
                                            : openSidebar(marker, null),
                                      ),
                                      SizedBox(width: 10),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              Color.fromARGB(255, 35, 97, 146),
                                        ),
                                        icon: Icon(Icons.check_circle_rounded, size: 18),
                                        label: Text("Save"),
                                        onPressed: isImage
                                            ? () => updateImageSelection(image, _sidebarImageName.text)
                                            : () => updateTextSelection(
                                                marker!,
                                                _sidebarText.text,
                                                _sidebarLabel,
                                                _sidebarLang),
                                      ),
                                    ],
                                  )
                                else
                                  Center(
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 35, 97, 146),
                                      ),
                                      icon: Icon(Icons.border_color_rounded, size: 18),
                                      label: Text("Edit"),
                                      onPressed: () =>
                                          _sidebarEdit.value = !_sidebarEdit.value,
                                    ),
                                  ),

                                SizedBox(height: 8),

                                Center(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red.shade400,
                                    ),
                                    icon: Icon(Icons.delete, size: 18),
                                    label: Text("Delete Selection"),
                                    onPressed: deleteSelection,
                                  ),
                                ),

                                SizedBox(height: 20),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  )
                : SizedBox.shrink();
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
      final color = TEIlabels[_selections.length + 1] ?? Color.fromARGB(255, 135, 209, 230);
      
      if (fragments.isNotEmpty) {
        _pendingSelection = TextSelection(
          text: selectedText,
          bounds: pdfRect,
          pageNumber: topLeft.page.pageNumber,
          globalRect: _getGlobalRect(selRect),
          label: 'Selection ${_selections.length + 1}',
          color: color,
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
    t.color = TEIlabels[label] as Color;

    closeSidebar();
  }

  // Update an ImageAnnotation from the sidebar
  void updateImageSelection(ImageAnnotation img, String name) {
    ImageAnnotation i = _imageAnnotations.firstWhere((i) => i == img);
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
                  const Text('Category:', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    value: dropdownLabel,
                    isExpanded: true,
                    items: TEIlabels.keys.map((String label) {
                      return DropdownMenuItem(value: label, child: Text(label));
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateDialog(() => dropdownLabel = newValue!);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Language:', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    value: dropdownLanguage,
                    isExpanded: true,
                    items: TEIlanguages.map((String language) {
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
                    _finalizeTextSelection(selection, dropdownLabel, dropdownLanguage);
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
                  const Text('Custom Label:', style: TextStyle(fontWeight: FontWeight.bold)),
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

    final color = TEIlabels[newLabel] ?? Color.fromARGB(255, 135, 209, 230);
    final newMarker = PdfMarker(
      color: color.withAlpha(100),
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
    final color = Color.fromARGB(255, 135, 209, 230);
    
    final timestamp = DateTime.now();
    final fileName = '${imageType.toLowerCase()}_page${pageNumber}_${label}_$timestamp.png';
    
    await _saveImageToFile(pixels, fileName);
    
    _imageAnnotations.add(ImageAnnotation(
      imageBytes: pixels,
      fileName: fileName,
      bounds: pdfRect,
      pageNumber: pageNumber,
      name: label,
      color: color,
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
        ..color = imageAnnotation.color.withAlpha(100)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(documentRect, paint);
      
      final paragraph = _buildParagraph(
        imageAnnotation.name, 
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

    // Combine TextSelections and ImageAnnotations into one list
    List<PageItem> x = _selections.values.toList();
    List<PageItem> pageItems = x + _imageAnnotations;

    // Sort the list into pages
    pageItems.sort(pageSort);
    final Map<int, List<PageItem>> pages = {};
    for (var item in pageItems) {
      int num = item.pageNumber;
      pages.update(num, (value) => value + [item], ifAbsent: () => [item]);
    }

    // Create XML file
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');

    xml.writeln('<text>');
    xml.writeln(' <body>');

    for (var page in pages.entries) {
      xml.writeln('   <pb n="${page.key}"/>');
      xml.writeln('   <div type = "page" n="${page.key}">');
      for(var item in page.value) {
        if (item is ImageAnnotation) {
          xml.writeln('     <graphic url="${item.fileName}"/>');
        } else {

        }
      }
      xml.writeln('   </div>');
    }

    xml.writeln(' </body>');
    xml.writeln('</text>');

    // xml.writeln('<pdfExtractions>');

    // xml.writeln('  <textExtractions>');
    // int i = 1;
    // for (TextSelection s in _selections.values) {
    //   xml.writeln('    <textExtraction index="$i">');
    //   xml.writeln('      <label>${_escapeXml(s.label)}</label>');
    //   xml.writeln('      <language>${_escapeXml(s.language)}</language>');
    //   xml.writeln('      <page>${s.pageNumber}</page>');
    //   xml.writeln('      <text>${_escapeXml(s.text)}</text>');
    //   xml.writeln(
    //     '      <bounds left="${s.bounds.left}" top="${s.bounds.top}" right="${s.bounds.right}" bottom="${s.bounds.bottom}" />'
    //   );
    //   xml.writeln('    </textExtraction>');
    //   i++;
    // }
    // xml.writeln('  </textExtractions>');

    // xml.writeln('  <imageExtractions>');
    // for (int j = 0; j < _imageAnnotations.length; j++) {
    //   final img = _imageAnnotations[j];
    //   xml.writeln('    <imageExtraction index="${j + 1}">');
    //   xml.writeln('      <file>${_escapeXml(img.fileName)}</file>');
    //   xml.writeln('      <type>${_escapeXml(img.type)}</type>');
    //   xml.writeln('      <name>${_escapeXml(img.name)}</name>');
    //   xml.writeln('      <page>${img.pageNumber}</page>');
    //   xml.writeln(
    //     '      <bounds left="${img.bounds.left}" top="${img.bounds.top}" right="${img.bounds.right}" bottom="${img.bounds.bottom}" />'
    //   );
    //   xml.writeln('      <sizeBytes>${img.imageBytes.length}</sizeBytes>');
    //   xml.writeln('    </imageExtraction>');
    // }
    // xml.writeln('  </imageExtractions>');

    // xml.writeln('</pdfExtractions>');

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

abstract class PageItem {
  PdfRect get bounds;
  int get pageNumber;
}

// Sorting comparator for PageItems
int pageSort(PageItem a, PageItem b) {
  // Compare page number
  if (a.pageNumber < b.pageNumber) {
    return -1;
  } else if (a.pageNumber > b.pageNumber) {
    return 1;
  // If same page, compare bounds
  } else {
    // Compare bounds top
    if (a.bounds.top < b.bounds.top) {
      return -1;
    } else if (a.bounds.top > b.bounds.top) {
      return 1;
    // Compare bounds left
    } else {
      if (a.bounds.left < b.bounds.left) {
        return -1;
      } else if (a.bounds.left > b.bounds.left) {
        return 1;
      } else {
        return 0;
      }
    }
  }
}

class TextSelection implements PageItem {
  String text;
  @override
  final PdfRect bounds;
  @override
  final int pageNumber;
  final Rect globalRect;
  String label;
  Color color;
  String language;

  TextSelection({
    required this.text,
    required this.bounds,
    required this.pageNumber,
    required this.globalRect,
    required this.label,
    required this.color,
    required this.language,
  });

  TextSelection copyWith({
    String? text,
    PdfRect? bounds,
    int? pageNumber,
    Rect? globalRect,
    String? label,
    Color? color,
    String? language,
  }) {
    return TextSelection(
      text: text ?? this.text,
      bounds: bounds ?? this.bounds,
      pageNumber: pageNumber ?? this.pageNumber,
      globalRect: globalRect ?? this.globalRect,
      label: label ?? this.label,
      color: color ?? this.color,
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

class ImageAnnotation implements PageItem {
  final Uint8List imageBytes;
  final String fileName;
  @override
  final PdfRect bounds;
  @override
  final int pageNumber;
  String name;
  Color color;

  ImageAnnotation({
    required this.imageBytes,
    required this.fileName,
    required this.bounds,
    required this.pageNumber,
    required this.name,
    required this.color,
  });
}