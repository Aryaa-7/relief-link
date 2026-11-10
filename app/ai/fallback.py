"""Rule-based triage. Used only when Gemma answered but gave unusable output (or timed out
repeatedly). It is NOT used while the AI server is simply unreachable (reports stay pending).
If no keyword matches it does NOT guess an emergency: it returns category "other" for human review."""
import re

from ..models import Category, Triage

KEYWORDS = {
    Category.medical: ["insulin", "bleeding", "injur", "doctor", "medicine", "hospital", "dawai", "pregnan"],
    Category.rescue: ["trapped", "stuck", "collapsed", "drown", "fasse", "fase", "rescue"],
    Category.food: ["food", "hungry", "khana", "ration", "starv"],
    Category.water: ["water", "paani", "pani", "thirst"],
    Category.shelter: ["shelter", "roof", "homeless", "tent", "ghar"],
}
URGENT = ["trapped", "bleeding", "insulin", "drown", "collapsed", "fasse", "unconscious"]


def rule_triage(text: str) -> Triage:
    low = text.lower()
    category = None
    for cat, words in KEYWORDS.items():
        if any(w in low for w in words):
            category = cat
            break
    if category is None:
        return Triage(
            severity=1, category=Category.other, people_affected=0, location_text="", needs=[],
            language_detected="und", summary_english=text[:140],
            suggested_action="No keyword matched. Review manually.")
    m = re.search(r"\d+", text)
    people = int(m.group()) if m else 1
    severity = 2 + (2 if any(w in low for w in URGENT) else 0) + (1 if people >= 3 else 0)
    return Triage(
        severity=min(severity, 5), category=category, people_affected=people,
        location_text="", needs=[category.value], language_detected="und",
        summary_english=text[:140], suggested_action=f"Send {category.value} team (rule-based guess)")