import 'package:flutter/material.dart';

import 'homepage.dart';

/// Implements the root widget for the app itself
class EbookMaker extends StatelessWidget {
  const EbookMaker({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eBook Maker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Homepage(title: 'eBook Maker Home Page'),
    );
  }
}
