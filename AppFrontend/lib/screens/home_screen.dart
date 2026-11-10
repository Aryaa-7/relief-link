import 'dart:async';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../state.dart';
import 'places_screen.dart';
import 'report_screen.dart';
import 'reports_screen.dart';
import 'resources_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  StreamSubscription<String>? _tapSub;

  @override
  void initState() {
    super.initState();
    _tapSub = NotificationService.instance.taps.listen(_openReport);
    final launch = NotificationService.instance.launchPayload;
    if (launch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openReport(launch));
    }
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    super.dispose();
  }

  void _openReport(String id) {
    final r = widget.state.reportById(id);
    if (r == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReportDetail(report: r)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final pages = [
      ReportScreen(state: s),
      ReportsScreen(state: s),
      ResourcesScreen(state: s),
      PlacesScreen(state: s),
    ];
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('ReliefLink'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                avatar: Icon(Icons.circle, size: 12, color: s.online ? Colors.green : Colors.red),
                label: Text(s.online ? 'Hub online' : 'Offline'
                    '${s.queue.isEmpty ? '' : ' · ${s.queue.length} queued'}'),
                visualDensity: VisualDensity.compact,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SettingsScreen(state: s))),
            ),
          ],
        ),
        body: pages[_tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.add_alert), label: 'Report'),
            NavigationDestination(icon: Icon(Icons.list_alt), label: 'Reports'),
            NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Resources'),
            NavigationDestination(icon: Icon(Icons.place), label: 'Places'),
          ],
        ),
      ),
    );
  }
}