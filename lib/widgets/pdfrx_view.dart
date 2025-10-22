import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PDF extends StatefulWidget {
  final bool selectMode; // Track if select mode is on
  
  const PDF({super.key, required this.selectMode});

  @override
  State<PDF> createState() => _State();
}

class _State extends State<PDF> {
  Rect? _selectionRect; // Selection rectangle
  Offset? _startOffset; // Selection start point
  bool _isSelecting = false; // Track selection activity

  @override
  void didUpdateWidget(PDF oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Clear any selection when selectMode is turned off
    if (oldWidget.selectMode && !widget.selectMode) {
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // PDF Viewer
        Listener(
          // Rename dart's built ins to our custom methods  
          // Check if select mode is on
          onPointerDown: widget.selectMode ? _onSelectStart : null,
          onPointerMove: widget.selectMode ? _onSelectUpdate : null,
          onPointerUp: widget.selectMode ? _onSelectEnd : null,
          child: PdfViewer.asset('assets/sample.pdf'),
        ),
        
        // Adds visual selection overlay so user can see selection box
        if (_selectionRect != null && widget.selectMode)
          Positioned(
            left: _selectionRect!.left,
            top: _selectionRect!.top,
            child: Container(
              width: _selectionRect!.width,
              height: _selectionRect!.height,
              decoration: BoxDecoration(
                color: Color(0x4D1976D2),
                border: Border.all(
                  color: Colors.blue,
                  width: 2.0,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Method for when there's a click to start a selection
  void _onSelectStart(PointerDownEvent event) {
    setState(() {
      _startOffset = event.localPosition;
      _selectionRect = Rect.fromPoints(_startOffset!, _startOffset!);
      _isSelecting = true;
    });
  }

  // Method to update the selection rectangle as it changes 
  void _onSelectUpdate(PointerMoveEvent event) {
    if (!_isSelecting || !widget.selectMode) return;
    
    setState(() {
      final currentOffset = event.localPosition;
      _selectionRect = Rect.fromPoints(_startOffset!, currentOffset);
    });
  }

  // Method for when the selection rectangle ends 
  void _onSelectEnd(PointerUpEvent event) {
    setState(() {
      _isSelecting = false;
    });
    
    // Print the selected area coordinates for now (do more with the _selectionRect later)
    if (_selectionRect != null && widget.selectMode) {
      print('Selected area: ${_selectionRect!}');
      print('Top-left: (${_selectionRect!.left}, ${_selectionRect!.top})');
      print('Size: ${_selectionRect!.width} x ${_selectionRect!.height}');
    }
  }

  // Clear selection rectangle
  void _clearSelection() {
    setState(() {
      _selectionRect = null;
      _startOffset = null;
      _isSelecting = false;
    });
  }

}