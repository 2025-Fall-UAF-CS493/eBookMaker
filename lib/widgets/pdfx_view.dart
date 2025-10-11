import 'package:flutter/widgets.dart';
import 'package:pdfx/pdfx.dart';

class PDFx extends StatefulWidget {
  const PDFx({super.key});

  @override
  State<PDFx> createState() => _State();
}

class _State extends State<PDFx> {

  late final PdfControllerPinch pdfControllerPinch;

  @override
  void initState() {
    super.initState();

    pdfControllerPinch = PdfControllerPinch(
      document: PdfDocument.openAsset('assets/sample.pdf'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewPinch(controller: pdfControllerPinch);
  }
}
