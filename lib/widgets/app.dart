import 'package:flutter/material.dart';

import 'homepage.dart';

/// Implements the root widget for the app itself
class EbookMaker extends StatelessWidget {
  const EbookMaker({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eBook Maker',
      home: const Homepage(),
    );
  }
}
