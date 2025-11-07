import 'package:flutter/material.dart';
import 'pdfrx_view.dart';   // Use platform-agnostic PDF viewer with pdfrx

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
  late final ValueNotifier<bool> selectModeNotifier;
  late final PDF pdfWidget;

  @override
  void initState() {
    super.initState();
    selectModeNotifier = ValueNotifier(false);
    pdfWidget = PDF(selectModeNotifier: selectModeNotifier);
  }

  @override
  void dispose() {
    selectModeNotifier.dispose();
    super.dispose();
  }

  int currentPage = 1;

  @override
  Widget build(BuildContext context) {
    return Column (
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: selectModeNotifier,
            builder: (_, selectMode, _) {
              return ElevatedButton(
                child: Text(selectMode ? "Selecting" : "Select"),
                onPressed: () => selectModeNotifier.value = !selectMode,
                );
            }
          ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ValueListenableBuilder<bool>(
                valueListenable: selectModeNotifier,
                builder: (_, selectMode, _) {
                  return MouseRegion(
                    cursor: selectModeNotifier.value ? SystemMouseCursors.precise : SystemMouseCursors.basic,
                    child: pdfWidget, // Pass the selectMode state
                  );
                },
              )
            )
          )
        ]
      );
  }
}