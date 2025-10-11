import 'package:flutter/widgets.dart';
import 'package:pdfx/pdfx.dart';

class PDF extends StatefulWidget {
  const PDF({super.key});

  @override
  State<PDF> createState() => _State();
}

class _State extends State<PDF> {

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
