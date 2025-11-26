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
          bodyLarge: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          bodyMedium: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          bodySmall: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          titleLarge: GoogleFonts.barlow(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 17, 28, 78)
          ),
          titleMedium: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          titleSmall: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          displayLarge: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          displayMedium: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          displaySmall: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          labelLarge: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          labelMedium: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          labelSmall: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          headlineLarge: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          headlineMedium: GoogleFonts.barlow(fontWeight: FontWeight.w500),
          headlineSmall: GoogleFonts.barlow(fontWeight: FontWeight.w500)
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
        centerTitle: false,
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

  void _showHelp() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text(
          'eBook Maker - Help Guide',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpSection('Getting Started', [
                '1. Click "Open File" to load a PDF document',
                '2. Press "Select" to enable selection tools',
                '3. Use the sidebar to manage your selections'
              ]),
              const SizedBox(height: 16),
              _buildHelpSection('Selecting Text', [
                '• In Select mode, click and drag to select text areas',
                '• A popup will appear allowing you to label as Text or Image',
                '• For text: Choose category (Title, Caption, etc.) and language',
                '• Text selections appear with highlights'
              ]),
              const SizedBox(height: 16),
              _buildHelpSection('Extracting Images', [
                '• In Select mode, click and drag to select image areas',
                '• Choose "Image" from the selection popup',
                '• Label the image type and provide a custom name',
                '• Images are saved as PNG files and appear with highlights'
              ]),
              const SizedBox(height: 16),
              _buildHelpSection('Managing Selections', [
                '• Click on any selection to view/edit in sidebar',
                '• Use "Edit" button to modify labels and text content',
                '• Delete unwanted selections with the "Delete" button',
                '• Export all data as XML using the "Export" button'
              ]),
            ],
          ),
        ),
        actions: [
          FilledButton.icon(
            label: const Text("Close"),
            onPressed: () {
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.highlight_off_rounded, size: 18)
          ),
        ],
      );
    },
  );
}

Widget _buildHelpSection(String title, List<String> points) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Color.fromARGB(255, 17, 28, 78),
        ),
      ),
      const SizedBox(height: 8),
      ...points.map((point) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          ' $point',
          style: const TextStyle(fontSize: 16),
        ),
      )),
    ],
  );
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
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              ValueListenableBuilder<PdfDocumentRef?>(
                valueListenable: documentRef,
                builder: (context, docRef, _) {
                  return Text(
                    'Current open file: ${_fileName(docRef?.key.sourceName) ?? 'No document loaded'}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  );
                },
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: selectModeNotifier,
                builder: (_, selectMode, _) {
                  return FilledButton.icon(
                    style: const ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll<Color>(Color.fromARGB(255, 255, 205, 0)),
                    ),
                    icon: const Icon(Icons.crop_free_rounded, size: 18, color: Color.fromARGB(255, 17, 28, 78)),
                    label: Text(
                      selectMode ? "Selecting On" : "Select", 
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
              const SizedBox(width: 10),
              FilledButton.icon(
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                onPressed: _triggerExport,
                label: const Text(
                  'Export', 
                  style: TextStyle(
                  fontSize: 14,
                  ),
                ), 
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                icon: const Icon(Icons.description_rounded, size: 18),
                onPressed: openFile,
                label: const Text(
                  'Open File', 
                  style: TextStyle(
                  fontSize: 14,
                  ),),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                onPressed: _showHelp,
                label: const Text(
                  'Help', 
                  style: TextStyle(
                  fontSize: 14,
                  ),
                ), 
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