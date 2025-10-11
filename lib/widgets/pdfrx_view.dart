import 'package:flutter/widgets.dart';
import 'package:pdfx/pdfx.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => HomepageContent();
}

class HomepageContent extends State<Homepage> {

  late final PdfController pdfController;

  @override
  void initState() {
    super.initState();

    pdfController = PdfController(
      document: PdfDocument.openAsset('assets/sample.pdf'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PdfView(controller: pdfController);
  }
}
