import 'package:flutter/material.dart';
import 'screens/push_to_talk_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MozhiApp());
}

class MozhiApp extends StatelessWidget {
  const MozhiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mozhi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const PushToTalkScreen(),
    );
  }
}
