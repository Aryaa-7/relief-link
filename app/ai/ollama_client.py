"""Talks to Ollama on the Mac over the local network (plain HTTP, no internet needed)."""
import httpx

from ..runtime import rt


class OllamaUnavailable(Exception):
    """Mac unreachable / Ollama down / model not installed. Reports stay pending."""


class OllamaTimeout(OllamaUnavailable):
    """Mac reachable but too slow to answer."""


def _base() -> str:
    return rt.base_url.rstrip("/")


def ping() -> list[str]:
    """Returns installed model names, or raises OllamaUnavailable."""
    try:
        r = httpx.get(_base() + "/api/tags", timeout=httpx.Timeout(4.0))
        r.raise_for_status()
        return [m.get("name", "") for m in r.json().get("models", [])]
    except (httpx.HTTPError, ValueError) as e:
        raise OllamaUnavailable(f"{type(e).__name__}: {e}") from e


def chat_json(messages: list[dict], schema: dict) -> str:
    body = {
        "model": rt.model, "messages": messages, "stream": False, "format": schema,
        "keep_alive": "30m", "options": {"temperature": 0, "num_predict": 400},
    }
    try:
        r = httpx.post(_base() + "/api/chat", json=body, timeout=httpx.Timeout(120.0, connect=4.0))
    except httpx.ReadTimeout as e:
        raise OllamaTimeout("AI server took too long to answer") from e
    except httpx.HTTPError as e:
        raise OllamaUnavailable(f"{type(e).__name__}: {e}") from e
    if r.status_code != 200:
        raise OllamaUnavailable(f"AI server returned HTTP {r.status_code}: {r.text[:200]}")
    try:
        return r.json()["message"]["content"]
    except (KeyError, ValueError) as e:
        raise OllamaUnavailable(f"Unexpected AI server response: {e}") from e
