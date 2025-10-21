// import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PDF extends StatefulWidget {
  const PDF({super.key});

  @override
  State<PDF> createState() => _State();
}

class _State extends State<PDF> {
  Rect? _selectionRect; // Selection rectangle
  Offset? _startOffset; // Selection start point
  bool _isSelecting = false; // Track selection activity

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // PDF Viewer
        GestureDetector(  
          // Rename dart's built ins to our custom methods  
          onPanStart: _onSelectStart,   
          onPanUpdate: _onSelectUpdate,
          onPanEnd: _onSelectEnd,
          child: PdfViewer.asset('assets/sample.pdf'),
        ),
        
        // Adds visual selection overlay so user can see selection box
        if (_selectionRect != null)
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
  void _onSelectStart(DragStartDetails details) {
    setState(() {
      _startOffset = details.localPosition;
      _selectionRect = Rect.fromPoints(_startOffset!, _startOffset!);
      _isSelecting = true;
    });
  }

  // Method to update the selection rectangle as it changes 
  void _onSelectUpdate(DragUpdateDetails details) {
    if (!_isSelecting) return;
    
    setState(() {
      final currentOffset = details.localPosition;
      _selectionRect = Rect.fromPoints(_startOffset!, currentOffset);
    });
  }

  // Method for when the selection rectangle ends 
  void _onSelectEnd(DragEndDetails details) {
    setState(() {
      _isSelecting = false;
    });
    
    // Print the selected area coordinates for now (do more with the _selectionRect later)
    if (_selectionRect != null) {
      print('Selected area: ${_selectionRect!}');
      print('Top-left: (${_selectionRect!.left}, ${_selectionRect!.top})');
      print('Size: ${_selectionRect!.width} x ${_selectionRect!.height}');
    }
  }

}