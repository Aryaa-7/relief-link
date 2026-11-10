import json
import logging

from ..models import Category, Triage
from . import ollama_client

log = logging.getLogger("relieflink.triage")

CATS = ["medical", "rescue", "food", "water", "shelter", "other"]
SCHEMA = {
    "type": "object",
    "properties": {
        "severity": {"type": "integer", "minimum": 1, "maximum": 5},
        "category": {"type": "string", "enum": CATS},
        "people_affected": {"type": "integer", "minimum": 0},
        "location_text": {"type": "string"},
        "needs": {"type": "array", "items": {"type": "string"}},
        "language_detected": {"type": "string"},
        "summary_english": {"type": "string"},
        "suggested_action": {"type": "string"},
    },
    "required": ["severity", "category", "people_affected", "location_text", "needs",
                 "language_detected", "summary_english", "suggested_action"],
}

SYSTEM = (
    "You triage messages sent to a disaster-relief hotline. Messages can be in any language "
    "(Hindi, Odia, English, mixed, with typos). Reply with ONE JSON object only, no other text.\n"
    "STEP 1: decide if the message is a real request for help or a report of an emergency/need. "
    "If it is NOT (greeting, test message, complaint about phone/Wi-Fi/app, general question, spam, "
    "gibberish, or too vague to act on), use category \"other\", severity 1, people_affected 0, needs [], "
    "and suggested_action \"No field action. Review manually.\" NEVER invent an emergency.\n"
    "STEP 2: only if it is a real need, fill the fields using ONLY facts written in the message. "
    "Do not add people, places or needs that are not written.\n"
    "Fields: severity (1-5), category (" + ", ".join(CATS) + "), people_affected (integer; the number "
    "stated, 1 for a single person, 0 if no person is mentioned), location_text (as written, empty if none), "
    "needs (short list), language_detected (ISO code), summary_english (one sentence), "
    "suggested_action (one short sentence).\n"
    "Severity: 5 = life at immediate risk (trapped, heavy bleeding, missing critical medicine); "
    "4 = urgent medical/rescue; 3 = serious need within hours; 2 = needed but stable; "
    "1 = minor, informational, or not a relief request. Pick the single most urgent category."
)

OTHER_ACTION = "No field action. Review manually."
SHOTS = [
    ("Roof collapsed on our house, 3 people trapped under it, one child bleeding. Near Gandhi school, Ward 4",
     {"severity": 5, "category": "rescue", "people_affected": 3, "location_text": "Near Gandhi school, Ward 4",
      "needs": ["rescue", "first aid"], "language_detected": "en",
      "summary_english": "Three people trapped under a collapsed roof, one child bleeding.",
      "suggested_action": "Send rescue team with medical support immediately."}),
    ("wifi not connected",
     {"severity": 1, "category": "other", "people_affected": 0, "location_text": "", "needs": [],
      "language_detected": "en",
      "summary_english": "Message about a Wi-Fi connection problem; not a relief request.",
      "suggested_action": OTHER_ACTION}),
    ("bhaiya hamare mohalle mein 2 din se peene ka paani nahi hai, 40 log hain, buzurg bimar hain",
     {"severity": 3, "category": "water", "people_affected": 40, "location_text": "our mohalla",
      "needs": ["drinking water"], "language_detected": "hi",
      "summary_english": "About 40 people have had no drinking water for 2 days; some elderly are ill.",
      "suggested_action": "Deliver drinking water; check on sick elderly."}),
    ("hello test 123",
     {"severity": 1, "category": "other", "people_affected": 0, "location_text": "", "needs": [],
      "language_detected": "en", "summary_english": "Test message; no request for help.",
      "suggested_action": OTHER_ACTION}),
    ("नदी का पानी घर में घुस आया है, 5 लोग छत पर फंसे हैं, एक बुजुर्ग को इंसुलिन चाहिए",
     {"severity": 5, "category": "rescue", "people_affected": 5, "location_text": "",
      "needs": ["boat rescue", "insulin"], "language_detected": "hi",
      "summary_english": "Five people stranded on a roof by floodwater; an elderly person needs insulin.",
      "suggested_action": "Send boat rescue with insulin."}),
    ("pani chahiye",
     {"severity": 2, "category": "water", "people_affected": 1, "location_text": "", "needs": ["drinking water"],
      "language_detected": "hi", "summary_english": "Someone needs drinking water; no other details.",
      "suggested_action": "Ask for location and number of people, then arrange water."}),
]


class TriageInvalid(Exception):
    """AI server answered, but twice with unusable output. args[0] = the last raw output."""


def _messages(text: str, hint, strict: bool) -> list[dict]:
    msgs = [{"role": "system", "content": SYSTEM}]
    for u, a in SHOTS:
        msgs += [{"role": "user", "content": u}, {"role": "assistant", "content": json.dumps(a, ensure_ascii=False)}]
    extra = (f"\n(language hint: {hint})" if hint else "")
    if strict:
        extra += "\nReturn ONLY valid JSON with all 8 fields and category exactly one of: " + ", ".join(CATS)
    msgs.append({"role": "user", "content": text + extra})
    return msgs


def run(text: str, lang_hint=None) -> Triage:
    """Raises OllamaUnavailable/OllamaTimeout (try later) or TriageInvalid (use fallback)."""
    content = ""
    for attempt in range(2):
        content = ollama_client.chat_json(_messages(text, lang_hint, strict=attempt == 1), SCHEMA)
        try:
            data = json.loads(content)
            if not isinstance(data, dict):
                raise ValueError("AI output is not a JSON object")
            data["category"] = str(data.get("category", "")).lower().strip()
            t = Triage.model_validate(data)
        except ValueError as e:  # JSONDecodeError and pydantic ValidationError both subclass it
            log.warning("Unusable AI output (attempt %d) for %r: %s | raw=%r",
                        attempt + 1, text[:60], str(e).splitlines()[0][:120], content[:300])
            continue
        if t.category == Category.other:  # guard: "other" can never look like an emergency
            t.severity, t.people_affected = 1, 0
            if not t.suggested_action:
                t.suggested_action = OTHER_ACTION
        return t
    raise TriageInvalid(content)