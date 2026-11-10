from fastapi import APIRouter, Response

from .. import store
from ..models import ResourceIn, ResourceOut

router = APIRouter(prefix="/resources", tags=["resources"])


@router.post("", response_model=ResourceOut, status_code=201,
             summary="Add a resource (idempotent on id)")
def add_resource(body: ResourceIn, response: Response):
    out, result = store.submit_resource(body)
    if result == "duplicate":
        response.status_code = 200
    return out


@router.get("", response_model=list[ResourceOut])
def list_resources():
    return store.list_resources()
