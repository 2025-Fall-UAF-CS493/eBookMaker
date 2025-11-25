import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'pdfrx_view.dart';
import 'package:google_fonts/google_fonts.dart';

class EbookMaker extends StatelessWidget {
  const EbookMaker({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eBook Maker',
      theme: ThemeData( 
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 35, 97, 146),
          brightness: Brightness.light,
        ),
        textTheme: TextTheme(
          titleLarge: GoogleFonts.barlow(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 17, 28, 78)
          ),
          bodyMedium: GoogleFonts.barlowSemiCondensed(),
          displaySmall: GoogleFonts.barlowSemiCondensed(),
        ),
      ),
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
      appBar: AppBar(
        title: const Text("Home Page"),
        toolbarHeight: 80.0,
      ),
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
  final ValueNotifier<bool> exportTrigger = ValueNotifier<bool>(false); 

  @override
  void initState() {
    super.initState();
    selectModeNotifier = ValueNotifier(false);
    openInitialFile();
  }

  @override
  void dispose() {
    selectModeNotifier.dispose();
    exportTrigger.dispose();
    super.dispose();
  }

  void _triggerExport() {
    exportTrigger.value = true;
  }

  Future<void> openInitialFile({bool useProgressiveLoading = true}) async {
    documentRef.value = PdfDocumentRefAsset('assets/sample.pdf', useProgressiveLoading: useProgressiveLoading);
  }

  Future<void> openFile({bool useProgressiveLoading = true}) async {
    if (selectModeNotifier.value) return;
    
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
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ValueListenableBuilder<bool>(
            valueListenable: selectModeNotifier,
            builder: (_, selectMode, _) {
              return FilledButton(
                style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll<Color>(Color.fromARGB(255, 255, 205, 0)),
                ),
                child: Text(
                  selectMode ? "Selecting" : "Select", 
                  style: TextStyle(
                  color: Color.fromARGB(255, 17, 28, 78),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => selectModeNotifier.value = !selectMode,
              );
            },
          ),
        ),
        Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
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
                onPressed: _triggerExport,
                child: const Text(
                  'Export', 
                  style: TextStyle(
                  fontSize: 14,
                  ),
                ), 
              ),
              const SizedBox(width: 15),
              FilledButton(
                onPressed: openFile,
                child: const Text(
                  'Open File', 
                  style: TextStyle(
                  fontSize: 14,
                  ),),
              ),
            ],
          ),
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
                return ValueListenableBuilder<bool>(
                  valueListenable: selectModeNotifier,
                  builder: (_, selectMode, _) {
                    return MouseRegion(
                      cursor: selectMode ? SystemMouseCursors.precise : SystemMouseCursors.basic,
                      child: PDF(
                        selectModeNotifier: selectModeNotifier,
                        documentRef: docRef,
                        exportTrigger: exportTrigger,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}