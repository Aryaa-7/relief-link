from fastapi import APIRouter, Depends

from .. import store
from ..deps import require_admin
from ..models import MatchOut

router = APIRouter(prefix="/matches", tags=["matches"])


@router.get("", response_model=list[MatchOut])
def list_matches():
    return store.list_matches()


@router.post("/run", dependencies=[Depends(require_admin)], summary="ADMIN: (re)run matching")
def run_matching():
    return {"matches_created": store.run_rule_matching()}
