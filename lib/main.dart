import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const EpdControllerApp());
}

class EpdControllerApp extends StatelessWidget {
  const EpdControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPD Controller',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}
