import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { admin, get } from "./api.js";

const CATEGORIES = ["medical", "rescue", "food", "water", "shelter", "other"];
const CASES = ["open", "assigned", "resolved"];

const fmtTime = (iso) => new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

function Stat({ label, value }) {
  return (
    <div className="stat">
      <b>{value}</b>
      <span>{label}</span>
    </div>
  );
}

function Row({ r, aiOnline, onCase }) {
  const t = r.triage;
  const pending = r.status === "processing";
  return (
    <tr className={r.case_status === "resolved" ? "resolved" : ""}>
      <td><span className={"sev s" + (t ? t.severity : 0)}>{t ? t.severity : "…"}</span></td>
      <td>{t ? t.category : "pending"}</td>
      <td>{t ? t.people_affected : "-"}</td>
      <td>
        {t && t.summary_english ? t.summary_english : r.raw_text}
        {t && t.suggested_action && <div className="tag">→ {t.suggested_action}</div>}
        {pending && <div className="tag">{aiOnline ? "AI is processing…" : "Waiting for AI server (report is saved)"}</div>}
      </td>
      <td>{t ? t.needs.join(", ") : ""}</td>
      <td className="tag">{r.triage_source || "-"}</td>
      <td className="tag">{fmtTime(r.received_at)}</td>
      <td>
        <select value={r.case_status} onChange={(e) => onCase(r.id, e.target.value)}>
          {CASES.map((c) => <option key={c}>{c}</option>)}
        </select>
      </td>
    </tr>
  );
}

function AIServerPanel() {
  const [cfg, setCfg] = useState(null);
  const [url, setUrl] = useState("");
  const [model, setModel] = useState("");

  const load = async () => {
    const d = await admin("/admin/ai-server");
    if (d) { setCfg(d); setUrl(d.base_url); setModel(d.model); }
  };
  const save = async () => {
    const d = await admin("/admin/ai-server", "PUT", { base_url: url, model });
    if (d) setCfg(d);
  };

  return (
    <details className="panel" onToggle={(e) => e.target.open && !cfg && load()}>
      <summary>AI server settings (Mac running Ollama)</summary>
      {cfg && (
        <div className="aiform">
          <label>Base URL <input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="http://MAC_IP:11434" /></label>
          <label>Model tag <input value={model} onChange={(e) => setModel(e.target.value)} placeholder="from `ollama list`" /></label>
          <button onClick={save}>Save &amp; test</button>
          <div className={"aistatus " + cfg.status}>
            Status: <b>{cfg.status}</b>{cfg.detail ? " — " + cfg.detail : ""}
          </div>
        </div>
      )}
    </details>
  );
}

export default function App() {
  const [items, setItems] = useState({});
  const [health, setHealth] = useState(null);
  const [online, setOnline] = useState(false);
  const [fCat, setFCat] = useState("");
  const [fCase, setFCase] = useState("");
  const since = useRef(null);

  const poll = useCallback(async () => {
    try {
      const q = since.current ? "?since=" + encodeURIComponent(since.current) : "";
      const [data, h] = await Promise.all([get("/reports" + q), get("/health")]);
      setItems((prev) => {
        const next = { ...prev };
        data.items.forEach((r) => { next[r.id] = r; });
        return next;
      });
      since.current = data.server_time;
      setHealth(h);
      setOnline(true);
    } catch {
      setOnline(false);
    }
  }, []);

  useEffect(() => {
    poll();
    const id = setInterval(poll, 3000);
    return () => clearInterval(id);
  }, [poll]);

  const setCase = async (id, value) => {
    const updated = await admin("/reports/" + id, "PATCH", { case_status: value });
    if (updated?.id) setItems((p) => ({ ...p, [updated.id]: updated }));
  };

  const runMatching = async () => {
    const r = await admin("/matches/run", "POST");
    if (r) window.alert("Matches created: " + r.matches_created);
  };

  const all = useMemo(() => Object.values(items), [items]);
  const stats = useMemo(() => {
    const open = all.filter((r) => r.case_status !== "resolved");
    return {
      total: all.length,
      critical: open.filter((r) => r.triage && r.triage.severity >= 4).length,
      people: open.reduce((n, r) => n + (r.triage ? r.triage.people_affected : 0), 0),
      pending: all.filter((r) => r.status === "processing").length,
    };
  }, [all]);

  const rows = useMemo(() => {
    let list = all;
    if (fCat) list = list.filter((r) => r.triage && r.triage.category === fCat);
    if (fCase) list = list.filter((r) => r.case_status === fCase);
    return [...list].sort(
      (a, b) => (b.triage ? b.triage.severity : 0) - (a.triage ? a.triage.severity : 0) ||
                new Date(b.received_at) - new Date(a.received_at));
  }, [all, fCat, fCase]);

  const aiOnline = health?.ollama === "online";

  return (
    <>
      <header>
        <h1>ReliefLink — Coordinator Dashboard</h1>
        <div className="pills">
          <span className={"pill " + (online ? "ok" : "bad")}>Hub {online ? "online" : "unreachable"}</span>
          {health && <span className={"pill " + (health.mongo === "ok" ? "ok" : "bad")}>MongoDB {health.mongo}</span>}
          {health && <span className={"pill " + (aiOnline ? "ok" : "bad")}>AI server {health.ollama}</span>}
          {health && health.queue_depth > 0 && <span className="pill warn">{health.queue_depth} waiting for AI</span>}
        </div>
      </header>
      <main>
        <div className="stats">
          <Stat label="Total" value={stats.total} />
          <Stat label="Open critical (4-5)" value={stats.critical} />
          <Stat label="People affected (open)" value={stats.people} />
          <Stat label="Pending AI" value={stats.pending} />
        </div>
        <div className="tools">
          <select value={fCat} onChange={(e) => setFCat(e.target.value)}>
            <option value="">All categories</option>
            {CATEGORIES.map((c) => <option key={c}>{c}</option>)}
          </select>
          <select value={fCase} onChange={(e) => setFCase(e.target.value)}>
            <option value="">All cases</option>
            {CASES.map((c) => <option key={c}>{c}</option>)}
          </select>
          <button onClick={runMatching}>Run matching</button>
        </div>
        <AIServerPanel />
        <div className="tablewrap">
          <table>
            <thead>
              <tr><th>Sev</th><th>Category</th><th>People</th><th>Summary</th><th>Needs</th><th>Source</th><th>Time</th><th>Case</th></tr>
            </thead>
            <tbody>{rows.map((r) => <Row key={r.id} r={r} aiOnline={aiOnline} onCase={setCase} />)}</tbody>
          </table>
          {rows.length === 0 && <div className="empty">No reports yet.</div>}
        </div>
      </main>
    </>
  );
}