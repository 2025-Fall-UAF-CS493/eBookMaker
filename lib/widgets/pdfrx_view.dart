import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

class PDF extends StatefulWidget {
  const PDF({super.key});

  @override
  State<PDF> createState() => _State();
}

class _State extends State<PDF> {

  @override
  Widget build(BuildContext context) {
    return PdfViewer.asset('assets/sample.pdf');
  }

}
