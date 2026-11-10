from fastapi import APIRouter

from ..models import LocationOut

router = APIRouter(prefix="/locations", tags=["locations"])

# SAMPLE DATA - replace with pins for your own demo area (data/locations.json later).
SAMPLE = [
    LocationOut(id="h1", name="Sample District Hospital", type="hospital", lat=20.2961, lng=85.8245),
    LocationOut(id="s1", name="Sample School Shelter", type="shelter", lat=20.3010, lng=85.8300),
    LocationOut(id="c1", name="Sample Relief Camp", type="camp", lat=20.2900, lng=85.8150),
    LocationOut(id="z1", name="Sample Safe Zone (stadium)", type="safe_zone", lat=20.3050, lng=85.8200),
]


@router.get("", response_model=list[LocationOut])
def list_locations():
    return SAMPLE
