import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';

class PlacesScreen extends StatefulWidget {
  final AppState state;
  const PlacesScreen({super.key, required this.state});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  List<Place> _items = [];
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
      final l = await widget.state.api.listLocations();
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

  IconData _icon(String t) {
    switch (t) {
      case 'hospital':
        return Icons.local_hospital;
      case 'shelter':
        return Icons.home;
      case 'camp':
        return Icons.holiday_village;
      default:
        return Icons.shield;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load places: $_error'),
            ),
          if (_error == null && _items.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No places listed.')),
          for (final p in _items)
            ListTile(
              leading: Icon(_icon(p.type)),
              title: Text(p.name),
              subtitle: Text('${p.type} · ${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}'),
            ),
        ],
      ),
    );
  }
}
