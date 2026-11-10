import 'package:flutter/material.dart';

import '../state.dart';

class ReportScreen extends StatefulWidget {
  final AppState state;
  const ReportScreen({super.key, required this.state});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _text = TextEditingController();
  String _lang = '';
  bool _gps = true;
  bool _sending = false;

  static const _langs = {
    '': 'Auto-detect',
    'en': 'English',
    'hi': 'Hindi',
    'or': 'Odia',
    'bn': 'Bengali',
  };

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    setState(() => _sending = true);
    await widget.state.submitReport(t, lang: _lang, attachGps: _gps);
    if (!mounted) return;
    _text.clear();
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(widget.state.online
          ? 'Report sent. The AI is triaging it.'
          : 'Saved on this phone. It will send when the hub is reachable.'),
    ));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Report an emergency', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Write in any language: Hindi, Hinglish, English...'),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          maxLines: 6,
          maxLength: 2000,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g. 3 log fasse hain, budhe ko insulin chahiye, road band hai',
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _lang,
          decoration: const InputDecoration(
              labelText: 'Language hint', border: OutlineInputBorder()),
          items: _langs.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _lang = v ?? ''),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Attach my GPS location'),
          value: _gps,
          onChanged: (v) => setState(() => _gps = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: const Text('Send report'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Works offline: reports are saved on this phone and sent automatically '
          'when the hub Wi-Fi is available.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
