import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  String _result = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.state.baseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    setState(() {
      _busy = true;
      _result = '';
    });
    await widget.state.setBaseUrl(_url.text);
    try {
      final h = await widget.state.api.health();
      setState(() => _result =
          'Connected. Hub ${h['version']}, mongo ${h['mongo']}, AI ${h['ollama']}, '
          'waiting for AI: ${h['queue_depth']}');
    } on ApiException catch (e) {
      setState(() => _result = 'Failed: ${e.message}');
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hub settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Hub address (the Windows laptop, port 8000). '
            'The phone must be on the same Wi-Fi or hotspot.'),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Hub URL',
            hintText: 'http://192.168.137.1:8000',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _saveAndTest,
          child: const Text('Save & test'),
        ),
        const SizedBox(height: 12),
        Text(_result),
        const SizedBox(height: 24),
        Text('Queued reports: ${widget.state.queue.length}'),
      ]),
    );
  }
}
