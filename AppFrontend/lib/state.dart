import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'models.dart';
import 'services/notification_service.dart';

/// Holds settings, the offline queue and cached reports. Syncs every few seconds.
class AppState extends ChangeNotifier {
  static const defaultUrl = 'http://192.168.137.1:8000';

  late SharedPreferences _p;
  String baseUrl = defaultUrl;
  List<Map<String, dynamic>> queue = []; // pending ReportIn json objects
  final Map<String, Report> _reports = {};
  String? _since;
  bool online = false;
  String? lastError;
  bool syncing = false;
  Timer? _timer;
  final Set<String> _mine = {}; // ids of reports sent from this phone
  final Set<String> _notified = {}; // ids already notified, so each notifies once

  Api get api => Api(baseUrl);

  Report? reportById(String id) => _reports[id];

  List<Report> get reports {
    final l = _reports.values.toList();
    l.sort((a, b) => (b.receivedAt ?? DateTime(0)).compareTo(a.receivedAt ?? DateTime(0)));
    return l;
  }

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    baseUrl = _p.getString('base_url') ?? defaultUrl;
    _since = _p.getString('since');
    _mine.addAll(_p.getStringList('mine') ?? []);
    _notified.addAll(_p.getStringList('notified') ?? []);
    for (final s in _p.getStringList('queue') ?? []) {
      queue.add(jsonDecode(s) as Map<String, dynamic>);
    }
    for (final s in _p.getStringList('reports') ?? []) {
      final r = Report.fromJson(jsonDecode(s) as Map<String, dynamic>);
      _reports[r.id] = r;
    }
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => syncNow());
    syncNow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> setBaseUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    baseUrl = u;
    _since = null; // refetch everything from the new hub
    await _p.setString('base_url', baseUrl);
    await _p.remove('since');
    notifyListeners();
    syncNow();
  }

  Future<void> _saveQueue() =>
      _p.setStringList('queue', queue.map(jsonEncode).toList());

  Future<void> _saveReports() => _p.setStringList(
      'reports', _reports.values.map((r) => jsonEncode(r.json)).toList());

  Future<Map<String, double>?> _gps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (_) {
      return null;
    }
  }

  /// Saves the report locally first (never lost), then tries to send.
  /// [gps] = coordinates chosen by the volunteer (place list or typed). If null and
  /// [attachGps] is true, the phone's location is read. If both are off, no location is sent.
  Future<void> submitReport(String text,
      {String? lang, bool attachGps = false, Map<String, double>? gps}) async {
    final item = <String, dynamic>{
      'id': const Uuid().v4(),
      'raw_text': text.trim(),
      'client_created_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (lang != null && lang.isNotEmpty) item['lang_hint'] = lang;
    if (gps != null) {
      item['gps'] = gps;
    } else if (attachGps) {
      final g = await _gps();
      if (g != null) item['gps'] = g;
    }
    _mine.add(item['id'] as String);
    await _p.setStringList('mine', _mine.toList());
    queue.add(item);
    await _saveQueue();
    notifyListeners();
    syncNow();
  }

  /// Notify once when one of THIS phone's reports gets its AI triage result.
  Future<void> _maybeNotify(Report r) async {
    final t = r.triage;
    if (t == null || !_mine.contains(r.id) || _notified.contains(r.id)) return;
    _notified.add(r.id);
    await _p.setStringList('notified', _notified.toList());
    await NotificationService.instance.showTriaged(
      reportId: r.id,
      severity: t.severity,
      category: t.category,
      summary: t.summaryEnglish.isNotEmpty ? t.summaryEnglish : r.rawText,
    );
  }

  Future<void> syncNow() async {
    if (syncing) return;
    syncing = true;
    try {
      // 1) push queued reports
      while (queue.isNotEmpty) {
        final chunk = queue.take(100).toList();
        final results = await api.submitBatch(chunk);
        final done = <String>{};
        for (final it in chunk) {
          final id = it['id'] as String;
          final res = results[id];
          // created / duplicate = stored on the hub; rejected = hub will never accept it
          if (res == 'created' || res == 'duplicate' || res == 'rejected') done.add(id);
        }
        queue.removeWhere((q) => done.contains(q['id']));
        await _saveQueue();
        if (done.isEmpty) break;
      }
      // 2) pull updates
      final (serverTime, items) = await api.listReports(since: _since);
      for (final r in items) {
        _reports[r.id] = r;
        await _maybeNotify(r);
      }
      _since = serverTime;
      await _p.setString('since', serverTime);
      await _saveReports();
      online = true;
      lastError = null;
    } on ApiException catch (e) {
      online = !e.network;
      lastError = e.message;
    } catch (e) {
      online = false;
      lastError = e.toString();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}