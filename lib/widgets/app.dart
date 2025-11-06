import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

// Use **one** of the following:
//
//import 'pdfx_view.dart';  // Use platform-native   PDF viewer with pdfx
import 'pdfrx_view.dart'; 

class EbookMaker extends StatelessWidget {
  const EbookMaker({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eBook Maker',
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home Page"),
      ),
      body: PDFSelectionWindow()
    );
  }
}

class PDFSelectionWindow extends StatefulWidget {
  const PDFSelectionWindow({super.key});

  @override
  State<PDFSelectionWindow> createState() => _PDFSelectState();
}

class _PDFSelectState extends State<PDFSelectionWindow> {
  final controller = PdfViewerController();
  final documentRef = ValueNotifier<PdfDocumentRef?>(null);
  bool selectMode = false;
  int currentPage = 1;

  @override
  void initState() {
    super.initState();
    openInitialFile();
  }

  void _updateCursor() {
    setState(() {
      selectMode = !selectMode;
    });
  }

  Future<void> openInitialFile({bool useProgressiveLoading = true}) async {
    documentRef.value = PdfDocumentRefAsset('assets/sample.pdf', useProgressiveLoading: useProgressiveLoading);
  }
  
  Future<void> openFile({bool useProgressiveLoading = true}) async {
    final file = await fs.openFile(
      acceptedTypeGroups: [
        fs.XTypeGroup(label: 'PDF files', extensions: ['pdf']),
      ],
    );
    if (file == null) return;

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      documentRef.value = PdfDocumentRefData(
        bytes,
        sourceName: 'web-open-file%${file.name}',
        useProgressiveLoading: useProgressiveLoading,
      );
    } else {
      documentRef.value = PdfDocumentRefFile(
        file.path,
        useProgressiveLoading: useProgressiveLoading,
      );
    }
  }

  static String? _fileName(String? path) {
    if (path == null) return null;
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          child: selectMode ? const Text("Selecting") : const Text("Select"),
          onPressed: () async {
            _updateCursor();
          },
        ),
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<PdfDocumentRef?>(
                valueListenable: documentRef,
                builder: (context, docRef, _) {
                  return Text(
                    _fileName(docRef?.key.sourceName) ?? 'No document loaded',
                    style: const TextStyle(fontSize: 16),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => openFile(),
              child: const Text('Open File'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: MouseRegion(
            cursor:
                selectMode ? SystemMouseCursors.precise : SystemMouseCursors.basic,
            child: PDF(selectMode: selectMode, currentPage: currentPage),
          ),
        ),
      ],
    );
  }
}