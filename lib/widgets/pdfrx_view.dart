import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

class PDFrx extends StatefulWidget {
  const PDFrx({super.key});

  @override
  State<PDFrx> createState() => _State();
}

class _State extends State<PDFrx> {

  @override
  Widget build(BuildContext context) {
    return PdfViewer.asset('assets/sample.pdf');
  }

}
