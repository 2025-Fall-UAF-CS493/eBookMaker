import 'package:flutter/material.dart';

// Use **one** of the following:
//
//import 'pdfx_view.dart';  // Use platform-native   PDF viewer with pdfx
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
  @override
  void initState() {
    super.initState();
  }
  bool selectMode = false;
  int currentPage = 1;

  void _updateCursor() {
    setState(() {
      selectMode = !selectMode;
    });
  }

// Page functions, have no integrated yet
/*
  void _incPage() {
    setState(() {
      currentPage += 1;
    });
  }
  void _decPage() {
    setState(() {
      if(currentPage >1){
        currentPage -=1;
      }
    });
  }
*/ 
  @override
  Widget build(BuildContext context) {
    return Column (
        children: [
          ElevatedButton(
            child: selectMode? const Text("Selecting") : const Text("Select"),
            onPressed: () async {
              _updateCursor();

            }),
          // Page functions, have no integrated yet
          /*
          ElevatedButton(
            child: const Text("Next"),
            onPressed: () {
              _incPage();
          },),
          ElevatedButton(
            child: const Text("Previous"),
            onPressed: () {
              _decPage();
          },),
          */
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: MouseRegion(
                cursor: selectMode ? SystemMouseCursors.precise : SystemMouseCursors.basic,
                child: PDF(selectMode: selectMode, currentPage: currentPage) // Pass the selectMode state
              ),
            ))
        ]
      );
  }
}