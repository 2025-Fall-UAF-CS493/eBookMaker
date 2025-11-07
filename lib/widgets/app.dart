import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

// Use one of the following:
// import 'pdfx_view.dart';  // Platform-native PDF viewer
import 'pdfrx_view.dart';    // Platform-agnostic PDF viewer

void main() {
  runApp(const EbookMaker());
}

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Home Page")),
      body: const PDFSelectionWindow(),
    );
  }
}

class PDFSelectionWindow extends StatefulWidget {
  const PDFSelectionWindow({super.key});

  @override
  State<PDFSelectionWindow> createState() => _PDFSelectState();
}

class _PDFSelectState extends State<PDFSelectionWindow> {
  late final ValueNotifier<bool> selectModeNotifier;
  final documentRef = ValueNotifier<PdfDocumentRef?>(null);

  @override
  void initState() {
    super.initState();
    selectModeNotifier = ValueNotifier(false);
    openInitialFile();
  }

  @override
  void dispose() {
    selectModeNotifier.dispose();
    super.dispose();
  }

  Future<void> openInitialFile({bool useProgressiveLoading = true}) async {
    documentRef.value =
        PdfDocumentRefAsset('assets/sample.pdf', useProgressiveLoading: useProgressiveLoading);
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
        ValueListenableBuilder<bool>(
          valueListenable: selectModeNotifier,
          builder: (_, selectMode, __) {
            return ElevatedButton(
              child: Text(selectMode ? "Selecting" : "Select"),
              onPressed: () => selectModeNotifier.value = !selectMode,
            );
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ValueListenableBuilder<PdfDocumentRef?>(
              valueListenable: documentRef,
              builder: (context, docRef, _) {
                if (docRef == null) {
                  return const Center(child: Text('No document loaded'));
                }
                return PDF(
                  selectModeNotifier: selectModeNotifier,
                  documentRef: docRef,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
