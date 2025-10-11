import 'package:flutter/material.dart';

// Use **one** of the following:
//
//import 'pdfx_view.dart';  // Use platform-native   PDF viewer with pdfx
import 'pdfrx_view.dart';   // Use platform-agnostic PDF viewer with pdfrx

/// Implements the root widget for the app itself
class EbookMaker extends StatelessWidget {
  const EbookMaker({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eBook Maker',
      home: const PDF(),
    );
  }
}
