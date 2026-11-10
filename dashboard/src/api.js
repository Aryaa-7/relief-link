// Relative URLs: works when served by FastAPI at /admin/ and through the Vite dev proxy.
const BASE = "/api/v1";
let pin = null; // admin PIN, kept in memory only

export async function get(path) {
  const r = await fetch(BASE + path);
  if (!r.ok) throw new Error("HTTP " + r.status);
  return r.json();
}

export async function admin(path, method = "GET", body) {
  if (!pin) pin = window.prompt("Admin PIN");
  if (!pin) return null;
  const r = await fetch(BASE + path, {
    method,
    headers: { "Content-Type": "application/json", "X-Admin-Pin": pin },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (r.status === 401) {
    pin = null;
    window.alert("Wrong PIN");
    return null;
  }
  const data = await r.json();
  if (!r.ok) {
    window.alert(data?.error?.message || "Request failed");
    return null;
  }
  return data;
}
