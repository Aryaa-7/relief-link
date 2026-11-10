import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  final state = AppState();
  await state.init();
  runApp(ReliefLinkApp(state: state));
}

class ReliefLinkApp extends StatelessWidget {
  final AppState state;
  const ReliefLinkApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReliefLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFC62828),
        useMaterial3: true,
      ),
      home: HomeScreen(state: state),
    );
  }
}