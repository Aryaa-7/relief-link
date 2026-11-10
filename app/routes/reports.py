from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import ValidationError

from .. import store
from ..deps import require_admin
from ..models import (BatchIn, BatchItemResult, BatchOut, CaseStatus, Category,
                      CaseUpdate, ReportIn, ReportList, ReportOut, SubmitAck)

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post("", response_model=SubmitAck, status_code=202,
             summary="Submit one report (idempotent on id)")
def submit(report: ReportIn, response: Response):
    out, result = store.submit_report(report)
    if result == "duplicate":
        response.status_code = 200
    return SubmitAck(id=out.id, status=out.status, received_at=out.received_at)


@router.post("/batch", response_model=BatchOut,
             summary="Offline sync: submit many reports; each is judged separately")
def submit_batch(body: BatchIn):
    results = []
    for item in body.reports:
        try:
            r = ReportIn.model_validate(item)
        except ValidationError as e:
            bad = e.errors()[0]
            results.append(BatchItemResult(
                id=str(item["id"]) if item.get("id") else None, result="rejected",
                error=".".join(str(x) for x in bad["loc"]) + ": " + bad["msg"]))
            continue
        _, result = store.submit_report(r)
        results.append(BatchItemResult(id=str(r.id), result=result))
    return BatchOut(results=results)


@router.get("", response_model=ReportList, summary="List reports (poll with ?since=)")
def list_reports(
    since: Optional[datetime] = None,
    category: Optional[Category] = None,
    min_severity: Optional[int] = Query(default=None, ge=1, le=5),
    case_status: Optional[CaseStatus] = None,
):
    if since and since.tzinfo is None:
        since = since.replace(tzinfo=timezone.utc)
    server_time = store.now()  # taken before the query so no update is missed between polls
    items = store.list_reports(since, category, min_severity, case_status)
    return ReportList(server_time=server_time, items=items)


@router.get("/{report_id}", response_model=ReportOut)
def get_report(report_id: UUID):
    r = store.get_report(report_id)
    if not r:
        raise HTTPException(404, "Report not found")
    return r


@router.patch("/{report_id}", response_model=ReportOut, dependencies=[Depends(require_admin)],
              summary="ADMIN: change case status")
def update_case(report_id: UUID, body: CaseUpdate):
    r = store.update_case(report_id, body.case_status)
    if not r:
        raise HTTPException(404, "Report not found")
    return r
