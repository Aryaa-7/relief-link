import logging
import socket
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import APIRouter, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import store
from .config import settings
from .models import Health
from .routes import admin, locations, matches, reports, resources
from .runtime import rt
from .worker import AIWorker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s: %(message)s")
log = logging.getLogger("relieflink")

VERSION = "0.2.0"
DASHBOARD_DIR = Path(__file__).resolve().parent.parent / "dashboard" / "dist"  # React production build


def lan_ips() -> list[str]:
    """All IPv4 addresses of this machine (works with no internet)."""
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    return sorted(i for i in ips if not i.startswith("127.")) or ["127.0.0.1"]


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        store.init_indexes()
        saved = store.get_setting("ai_server")
        if saved:  # an address saved from the dashboard wins over .env
            rt.base_url = saved.get("base_url", rt.base_url)
            rt.model = saved.get("model", rt.model)
    except Exception as e:
        log.error("MongoDB not reachable at %s (%s). Start MongoDB, then restart.", settings.mongo_url, e)

    ips = lan_ips()
    print("\n" + "=" * 56)
    print(" ReliefLink hub running")
    for ip in ips:
        print(f"  Phones / app server address : http://{ip}:{settings.port}")
    print(f"  Admin dashboard (this laptop): http://localhost:{settings.port}/admin/")
    print(f"  API docs                    : http://localhost:{settings.port}/docs")
    print(f"  AI server (Mac)             : {rt.base_url}  model={rt.model or '(not set)'}")
    print("=" * 56)
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(f"http://{ips[0]}:{settings.port}")
        qr.print_ascii(invert=True)
    except Exception:
        pass

    worker = AIWorker()
    worker.start()
    yield
    worker.stop()


app = FastAPI(title="ReliefLink API", version=VERSION, lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ---- one error format everywhere: {"error": {"code", "message"}} ----
CODES = {400: "bad_request", 401: "unauthorized", 404: "not_found", 422: "validation_error"}


@app.exception_handler(StarletteHTTPException)
async def http_error(request: Request, exc: StarletteHTTPException):
    return JSONResponse(status_code=exc.status_code, content={
        "error": {"code": CODES.get(exc.status_code, "error"), "message": str(exc.detail)}})


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    msg = "; ".join(f"{'.'.join(str(p) for p in e['loc'][1:])}: {e['msg']}" for e in exc.errors())
    return JSONResponse(status_code=422, content={"error": {"code": "validation_error", "message": msg}})


# ---- API v1 ----
api = APIRouter(prefix="/api/v1")
api.include_router(reports.router)
api.include_router(resources.router)
api.include_router(matches.router)
api.include_router(locations.router)
api.include_router(admin.router)


@api.get("/health", response_model=Health, tags=["system"])
def health():
    mongo = store.mongo_ok()
    return Health(status="ok" if mongo else "degraded", version=VERSION, server_time=store.now(),
                  mongo="ok" if mongo else "down", ollama=rt.status,
                  queue_depth=store.pending_count() if mongo else 0)


app.include_router(api)


@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse("/admin/")


# ---- React dashboard: the production build in dashboard/dist, served locally ----
if (DASHBOARD_DIR / "index.html").exists():
    app.mount("/admin", StaticFiles(directory=DASHBOARD_DIR, html=True), name="dashboard")
else:
    @app.get("/admin/", include_in_schema=False)
    def dashboard_missing():
        return HTMLResponse("<h3>Dashboard not built yet</h3><p>Run <code>cd dashboard</code>, "
                            "<code>npm install</code>, <code>npm run build</code>, then restart.</p>")
