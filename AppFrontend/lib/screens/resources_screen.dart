import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';

class ResourcesScreen extends StatefulWidget {
  final AppState state;
  const ResourcesScreen({super.key, required this.state});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  List<Resource> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final l = await widget.state.api.listResources();
      if (!mounted) return;
      setState(() {
        _items = l;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _AddResourceDialog(state: widget.state),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Could not load resources: $_error'),
                    ),
                  if (_error == null && _items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No resources registered yet.'),
                    ),
                  for (final r in _items)
                    ListTile(
                      leading: const Icon(Icons.inventory_2),
                      title: Text('${r.quantity} ${r.unit} ${r.type}'),
                      subtitle: Text(
                          '${r.locationText}${r.contact.isEmpty ? '' : ' · ${r.contact}'} · ${r.status}'),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add resource'),
      ),
    );
  }
}

class _AddResourceDialog extends StatefulWidget {
  final AppState state;
  const _AddResourceDialog({required this.state});

  @override
  State<_AddResourceDialog> createState() => _AddResourceDialogState();
}

class _AddResourceDialogState extends State<_AddResourceDialog> {
  String _type = 'food';
  final _qty = TextEditingController(text: '1');
  final _unit = TextEditingController();
  final _loc = TextEditingController();
  final _contact = TextEditingController();
  String? _error;
  bool _busy = false;

  static const _types = ['food', 'water', 'medicine', 'transport', 'shelter'];

  Future<void> _save() async {
    final q = int.tryParse(_qty.text.trim());
    if (q == null || q < 1) {
      setState(() => _error = 'Quantity must be 1 or more');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.api.addResource({
        'id': const Uuid().v4(),
        'type': _type,
        'quantity': q,
        'unit': _unit.text.trim(),
        'location_text': _loc.text.trim(),
        'contact': _contact.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _unit.dispose();
    _loc.dispose();
    _contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add resource'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _type = v ?? 'food'),
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          TextField(
              controller: _qty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity')),
          TextField(
              controller: _unit,
              decoration: const InputDecoration(labelText: 'Unit (e.g. packets, litres)')),
          TextField(
              controller: _loc,
              decoration: const InputDecoration(labelText: 'Where is it?')),
          TextField(
              controller: _contact,
              decoration: const InputDecoration(labelText: 'Contact')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
