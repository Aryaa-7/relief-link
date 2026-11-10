from fastapi import APIRouter, Depends, HTTPException

from .. import store
from ..ai import ollama_client
from ..deps import require_admin
from ..models import AIServerIn, AIServerOut
from ..runtime import rt

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


def _ai_out() -> AIServerOut:
    return AIServerOut(base_url=rt.base_url, model=rt.model, status=rt.status, detail=rt.detail)


@router.get("/check", summary="Lets a client verify the PIN")
def check():
    return {"ok": True}


@router.post("/reset", summary="Wipe all data (demo reset)")
def reset():
    store.reset()
    return {"ok": True}


@router.get("/ai-server", response_model=AIServerOut, summary="Current AI server (Mac) settings + status")
def get_ai_server():
    return _ai_out()


@router.put("/ai-server", response_model=AIServerOut,
            summary="Change the AI server address/model at runtime (no restart needed)")
def set_ai_server(body: AIServerIn):
    if body.base_url is not None:
        url = body.base_url.strip().rstrip("/")
        if not url.startswith(("http://", "https://")):
            raise HTTPException(400, "base_url must start with http:// or https://")
        rt.base_url = url
    if body.model is not None:
        rt.model = body.model.strip()
    store.set_setting("ai_server", {"base_url": rt.base_url, "model": rt.model})
    try:
        rt.set_online(ollama_client.ping())
    except ollama_client.OllamaUnavailable as e:
        rt.set_offline(str(e))
    return _ai_out()
