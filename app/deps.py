from typing import Optional

from fastapi import Header, HTTPException

from .config import settings


def require_admin(x_admin_pin: Optional[str] = Header(default=None)) -> None:
    """Admin-only endpoints need the header  X-Admin-Pin: <pin>."""
    if x_admin_pin != settings.admin_pin:
        raise HTTPException(status_code=401, detail="Admin PIN required or wrong")
