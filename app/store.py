"""MongoDB storage (local, on the Windows hub). Same function names/behaviour as the step-1
stub, so the API contract is unchanged. UUID string = _id, so retried submissions are ignored."""
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID, uuid4

from pymongo import MongoClient, ReturnDocument
from pymongo.errors import DuplicateKeyError

from .config import settings
from .models import (CaseStatus, Category, MatchOut, ReportIn, ReportOut, ResourceIn,
                     ResourceOut, ResourceType, Triage)

_client = MongoClient(settings.mongo_url, serverSelectionTimeoutMS=3000, tz_aware=True)
_db = _client[settings.mongo_db]
reports = _db["reports"]
resources = _db["resources"]
matches = _db["matches"]
app_settings = _db["settings"]


def now() -> datetime:
    return datetime.now(timezone.utc)


def init_indexes() -> None:
    reports.create_index([("status", 1), ("received_at", 1)])
    reports.create_index("updated_at")
    resources.create_index([("type", 1), ("status", 1)])


def mongo_ok() -> bool:
    try:
        _client.admin.command("ping")
        return True
    except Exception:
        return False


# ---------- reports ----------
def _report_out(doc: dict) -> ReportOut:
    return ReportOut.model_validate({**doc, "id": doc["_id"]})


def submit_report(r: ReportIn) -> tuple[ReportOut, str]:
    t = now()
    doc = {
        "_id": str(r.id), "raw_text": r.raw_text, "lang_hint": r.lang_hint,
        "gps": r.gps.model_dump() if r.gps else None,
        "client_created_at": r.client_created_at, "received_at": t, "updated_at": t,
        "status": "processing",       # pending until the AI worker (Mac) triages it
        "triage_source": None, "case_status": "open", "triage": None, "attempts": 0,
    }
    try:
        reports.insert_one(doc)
        return _report_out(doc), "created"
    except DuplicateKeyError:
        return _report_out(reports.find_one({"_id": str(r.id)})), "duplicate"


def list_reports(since: Optional[datetime], category: Optional[Category],
                 min_severity: Optional[int], case_status: Optional[CaseStatus]) -> list[ReportOut]:
    q: dict = {}
    if since:
        q["updated_at"] = {"$gt": since}
    if category:
        q["triage.category"] = category.value
    if min_severity:
        q["triage.severity"] = {"$gte": min_severity}
    if case_status:
        q["case_status"] = case_status.value
    items = [_report_out(d) for d in reports.find(q)]
    items.sort(key=lambda r: (-(r.triage.severity if r.triage else 0), -r.received_at.timestamp()))
    return items


def get_report(rid: UUID) -> Optional[ReportOut]:
    d = reports.find_one({"_id": str(rid)})
    return _report_out(d) if d else None


def update_case(rid: UUID, status: CaseStatus) -> Optional[ReportOut]:
    d = reports.find_one_and_update(
        {"_id": str(rid)}, {"$set": {"case_status": status.value, "updated_at": now()}},
        return_document=ReturnDocument.AFTER)
    return _report_out(d) if d else None


# ---------- AI worker helpers ----------
def next_pending() -> Optional[dict]:
    return reports.find_one({"status": "processing"}, sort=[("received_at", 1)])


def pending_count() -> int:
    return reports.count_documents({"status": "processing"})


def bump_attempts(rid: str) -> int:
    d = reports.find_one_and_update({"_id": rid}, {"$inc": {"attempts": 1}}, return_document=ReturnDocument.AFTER)
    return d["attempts"] if d else 0


def save_triage(rid: str, triage: Triage, source: str) -> None:
    reports.update_one({"_id": rid}, {"$set": {
        "status": "triaged", "triage": triage.model_dump(mode="json"),
        "triage_source": source, "updated_at": now()}})


# ---------- resources ----------
def submit_resource(r: ResourceIn) -> tuple[ResourceOut, str]:
    doc = {**r.model_dump(mode="python"), "_id": str(r.id), "status": "available", "received_at": now()}
    doc["id"] = str(r.id)
    doc["type"] = r.type.value
    try:
        resources.insert_one(doc)
        return ResourceOut.model_validate(doc), "created"
    except DuplicateKeyError:
        return ResourceOut.model_validate(resources.find_one({"_id": str(r.id)})), "duplicate"


def list_resources() -> list[ResourceOut]:
    return [ResourceOut.model_validate(d) for d in resources.find().sort("received_at", -1)]


# ---------- matches (rule-based) ----------
CATEGORY_TO_RESOURCE = {
    Category.medical: ResourceType.medicine, Category.food: ResourceType.food,
    Category.water: ResourceType.water, Category.shelter: ResourceType.shelter,
    Category.rescue: ResourceType.transport,
}


def list_matches() -> list[MatchOut]:
    return [MatchOut.model_validate({**d, "id": d["_id"]}) for d in matches.find()]


def run_rule_matching() -> int:
    matches.delete_many({})
    avail = list(resources.find({"status": "available"}))
    docs = []
    for rep in reports.find({"status": "triaged", "case_status": {"$ne": "resolved"}}):
        want_type = CATEGORY_TO_RESOURCE.get(Category(rep["triage"]["category"]))
        if want_type is None:  # category "other": nothing to match
            continue
        want = want_type.value
        res = next((x for x in avail if x["type"] == want), None)
        if res:
            docs.append({"_id": str(uuid4()), "report_id": rep["_id"], "resource_id": res["_id"],
                         "rank": 1, "source": "rule", "status": "suggested",
                         "reason": f"{want} available at {res.get('location_text') or 'unknown location'}"})
    if docs:
        matches.insert_many(docs)
    return len(docs)


# ---------- settings / reset ----------
def get_setting(key: str) -> Optional[dict]:
    d = app_settings.find_one({"_id": key})
    return d["value"] if d else None


def set_setting(key: str, value: dict) -> None:
    app_settings.update_one({"_id": key}, {"$set": {"value": value}}, upsert=True)


def reset() -> None:
    reports.delete_many({}); resources.delete_many({}); matches.delete_many({})