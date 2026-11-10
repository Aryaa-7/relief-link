import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';

Color severityColor(int s) {
  switch (s) {
    case 5:
      return const Color(0xFFB71C1C);
    case 4:
      return const Color(0xFFE65100);
    case 3:
      return const Color(0xFFF9A825);
    case 2:
      return const Color(0xFF558B2F);
    default:
      return const Color(0xFF2E7D32);
  }
}

class ReportsScreen extends StatelessWidget {
  final AppState state;
  const ReportsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final queued = state.queue;
    final reports = state.reports;
    if (queued.isEmpty && reports.isEmpty) {
      return const Center(child: Text('No reports yet.'));
    }
    return RefreshIndicator(
      onRefresh: state.syncNow,
      child: ListView(
        children: [
          for (final q in queued)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(q['raw_text'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Waiting to send (saved on this phone)'),
            ),
          for (final r in reports) _tile(context, r),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Report r) {
    final t = r.triage;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: t == null ? Colors.grey : severityColor(t.severity),
        foregroundColor: Colors.white,
        child: Text(t == null ? '…' : '${t.severity}'),
      ),
      title: Text(
        t != null && t.summaryEnglish.isNotEmpty ? t.summaryEnglish : r.rawText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(t == null
          ? 'AI is processing…'
          : '${t.category} · ${t.peopleAffected} people · case ${r.caseStatus}'),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReportDetail(report: r))),
    );
  }
}

class ReportDetail extends StatelessWidget {
  final Report report;
  const ReportDetail({super.key, required this.report});

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(v.isEmpty ? '-' : v)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = report.triage;
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _row('Your message', report.rawText),
        _row('Status', report.status),
        _row('Case', report.caseStatus),
        if (report.triageSource != null) _row('Triaged by', report.triageSource!),
        if (t != null) ...[
          const Divider(),
          _row('Severity', '${t.severity} / 5'),
          _row('Category', t.category),
          _row('People affected', '${t.peopleAffected}'),
          _row('Location', t.locationText),
          _row('Needs', t.needs.join(', ')),
          _row('Language', t.languageDetected),
          _row('Summary', t.summaryEnglish),
          _row('Suggested action', t.suggestedAction),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Waiting for the AI server. This updates automatically.'),
          ),
      ]),
    );
  }
}
