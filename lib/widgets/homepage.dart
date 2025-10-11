import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key, required this.title});

  final String title;

  @override
  State<Homepage> createState() => HomepageContent();
}

class HomepageContent extends State<Homepage> {

  late final PdfController pdfController;

  @override
  void initState() {
    super.initState();
    // Use PdfDocument.openAsset for bundled asset.
    pdfController = PdfController(
      document: PdfDocument.openAsset('assets/sample.pdf'),
    );
  }


  @override
  Widget build(BuildContext context) {

    return PdfView(controller: pdfController);
  }
}
