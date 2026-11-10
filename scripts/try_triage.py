"""Try the AI triage directly (no database, no hub needed). Run from the project folder:
    python scripts/try_triage.py                      # runs built-in samples
    python scripts/try_triage.py "wifi not connected" "2 log fase hain"
Uses OLLAMA_BASE_URL / OLLAMA_MODEL from .env (or the address saved from the dashboard)."""
import logging
import sys
import time

logging.basicConfig(level=logging.WARNING, format="  [%(name)s] %(message)s")
sys.path.insert(0, ".")
from app.ai import ollama_client, triage  # noqa: E402
from app.runtime import rt  # noqa: E402

try:  # an address saved from the dashboard wins over .env
    from app import store
    saved = store.get_setting("ai_server")
    if saved:
        rt.base_url, rt.model = saved.get("base_url", rt.base_url), saved.get("model", rt.model)
except Exception:
    pass

SAMPLES = [
    "wifi not connected", "hello", "asdfgh", "test message please ignore",
    "pani chahiye", "3 log fase hain, budhe ko insulin chahiye",
    "Our house is flooded, 6 people on the roof near the temple, need boat",
    "bahut bhookh lagi hai, 2 din se khana nahi mila, 10 bachche hain",
    "Roads are blocked and I am bored",
]
texts = sys.argv[1:] or SAMPLES
print(f"AI server: {rt.base_url}  model: {rt.model}\n")
for t in texts:
    start = time.time()
    try:
        r = triage.run(t)
        d = r.model_dump(mode="json")
        print(f"> {t}\n  sev={d['severity']} cat={d['category']} people={d['people_affected']}"
              f"  ({time.time()-start:.1f}s)\n  {d['summary_english']}\n  -> {d['suggested_action']}\n")
    except triage.TriageInvalid as e:
        raw = (e.args[0] if e.args else "")[:300]
        print(f"> {t}\n  INVALID output twice (the hub would use the rule-based fallback)\n  raw AI output: {raw!r}\n")
    except ollama_client.OllamaUnavailable as e:
        print(f"> {t}\n  AI server unavailable: {e}\n")
        break