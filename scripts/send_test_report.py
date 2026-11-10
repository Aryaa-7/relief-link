"""Quick test: python scripts/send_test_report.py [base_url] ["report text"]"""
import sys
import uuid

import httpx

base = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
text = sys.argv[2] if len(sys.argv) > 2 else "3 log fasse hain, budhe ko insulin chahiye, road band hai"
r = httpx.post(f"{base}/api/v1/reports", json={"id": str(uuid.uuid4()), "raw_text": text}, timeout=10)
print(r.status_code, r.json())
