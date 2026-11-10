// Data models. Field names match the hub's app/models.py (snake_case JSON).

DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class Triage {
  final int severity;
  final String category;
  final int peopleAffected;
  final String locationText;
  final List<String> needs;
  final String languageDetected;
  final String summaryEnglish;
  final String suggestedAction;

  Triage({
    required this.severity,
    required this.category,
    required this.peopleAffected,
    required this.locationText,
    required this.needs,
    required this.languageDetected,
    required this.summaryEnglish,
    required this.suggestedAction,
  });

  factory Triage.fromJson(Map<String, dynamic> j) => Triage(
        severity: (j['severity'] ?? 1) as int,
        category: (j['category'] ?? '') as String,
        peopleAffected: (j['people_affected'] ?? 1) as int,
        locationText: (j['location_text'] ?? '') as String,
        needs: ((j['needs'] ?? []) as List).map((e) => e.toString()).toList(),
        languageDetected: (j['language_detected'] ?? 'und') as String,
        summaryEnglish: (j['summary_english'] ?? '') as String,
        suggestedAction: (j['suggested_action'] ?? '') as String,
      );
}

class Report {
  final String id;
  final String rawText;
  final DateTime? receivedAt;
  final DateTime? updatedAt;
  final String status; // processing | triaged | failed
  final String? triageSource; // gemma | fallback
  final String caseStatus; // open | assigned | resolved
  final Triage? triage;
  final Map<String, dynamic> json; // original, for local caching

  Report({
    required this.id,
    required this.rawText,
    required this.receivedAt,
    required this.updatedAt,
    required this.status,
    required this.triageSource,
    required this.caseStatus,
    required this.triage,
    required this.json,
  });

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'] as String,
        rawText: (j['raw_text'] ?? '') as String,
        receivedAt: _dt(j['received_at']),
        updatedAt: _dt(j['updated_at']),
        status: (j['status'] ?? 'processing') as String,
        triageSource: j['triage_source'] as String?,
        caseStatus: (j['case_status'] ?? 'open') as String,
        triage: j['triage'] == null
            ? null
            : Triage.fromJson(j['triage'] as Map<String, dynamic>),
        json: j,
      );
}

class Resource {
  final String id;
  final String type;
  final int quantity;
  final String unit;
  final String locationText;
  final String contact;
  final String status;

  Resource({
    required this.id,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.locationText,
    required this.contact,
    required this.status,
  });

  factory Resource.fromJson(Map<String, dynamic> j) => Resource(
        id: j['id'] as String,
        type: (j['type'] ?? '') as String,
        quantity: (j['quantity'] ?? 0) as int,
        unit: (j['unit'] ?? '') as String,
        locationText: (j['location_text'] ?? '') as String,
        contact: (j['contact'] ?? '') as String,
        status: (j['status'] ?? 'available') as String,
      );
}

class Place {
  final String id;
  final String name;
  final String type; // hospital | shelter | camp | safe_zone
  final double lat;
  final double lng;

  Place({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
  });

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'].toString(),
        name: (j['name'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}
