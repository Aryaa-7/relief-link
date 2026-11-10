"""Live AI-server settings + status. Changeable at runtime (dashboard) so the Mac's
IP can be updated when switching networks, without restarting the backend."""
from .config import settings


class Runtime:
    def __init__(self) -> None:
        self.base_url = settings.ollama_base_url
        self.model = settings.ollama_model
        self.status = "unknown"   # unknown | online | offline | model_missing
        self.detail = ""

    @property
    def online(self) -> bool:
        return self.status == "online"

    def set_online(self, installed: list[str]) -> None:
        names = {n for n in installed} | {n.split(":")[0] for n in installed if n.endswith(":latest")}
        if not self.model:
            self.status, self.detail = "model_missing", "OLLAMA_MODEL is not set"
        elif self.model not in names:
            self.status = "model_missing"
            self.detail = f"Model '{self.model}' not installed on the AI server. Installed: {sorted(installed)}"
        else:
            self.status, self.detail = "online", ""

    def set_offline(self, why: str) -> None:
        self.status, self.detail = "offline", why


rt = Runtime()
