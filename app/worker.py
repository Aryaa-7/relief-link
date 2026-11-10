"""Background AI worker. MongoDB is the queue: every report with status='processing' is pending.
If the Mac is unreachable the report simply stays 'processing' and is retried automatically."""
import logging
import threading
import time

from . import store
from .ai import ollama_client
from .ai.fallback import rule_triage
from .ai.triage import TriageInvalid, run as run_triage
from .runtime import rt

log = logging.getLogger("relieflink.worker")
MAX_TIMEOUTS = 3  # after this many timeouts for one report, use the rule-based fallback


def refresh_ollama_status() -> None:
    try:
        rt.set_online(ollama_client.ping())
    except ollama_client.OllamaUnavailable as e:
        rt.set_offline(str(e))


class AIWorker(threading.Thread):
    def __init__(self) -> None:
        super().__init__(daemon=True, name="ai-worker")
        self._stop_evt = threading.Event()
        self._last_ping = 0.0

    def stop(self) -> None:
        self._stop_evt.set()

    def run(self) -> None:
        refresh_ollama_status()
        self._last_ping = time.time()
        while not self._stop_evt.is_set():
            try:
                busy = self._step()
            except Exception:
                log.exception("AI worker error (will retry)")
                busy = False
                self._stop_evt.wait(5)
            if not busy:
                self._stop_evt.wait(2)

    def _step(self) -> bool:
        doc = store.next_pending()
        interval = 15 if doc is None else 8
        if (doc is None or not rt.online) and time.time() - self._last_ping > interval:
            refresh_ollama_status()
            self._last_ping = time.time()
        if doc is None or not rt.online:
            return False  # nothing to do, or AI server down: reports stay pending

        rid = doc["_id"]
        try:
            triage, source = run_triage(doc["raw_text"], doc.get("lang_hint")), "gemma"
        except ollama_client.OllamaTimeout:
            if store.bump_attempts(rid) < MAX_TIMEOUTS:
                return False
            triage, source = rule_triage(doc["raw_text"]), "fallback"
        except ollama_client.OllamaUnavailable as e:
            rt.set_offline(str(e))
            log.warning("AI server unavailable, %s stays pending: %s", rid, e)
            return False
        except TriageInvalid:
            triage, source = rule_triage(doc["raw_text"]), "fallback"
        store.save_triage(rid, triage, source)
        log.info("report %s triaged by %s", rid, source)
        return True
