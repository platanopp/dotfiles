#!/usr/bin/env python3
"""Print a compact 7-day forecast as one JSON line.

Location comes from the public IP unless a latitude and longitude are passed
as arguments. Always prints JSON: on failure, an object with an "error" key,
so the shell can show a state rather than parsing an empty string.
"""

import json
import sys
import urllib.request

GEO_URL = "http://ip-api.com/json/?fields=status,city,lat,lon"
FORECAST_URL = (
    "https://api.open-meteo.com/v1/forecast"
    "?latitude={lat}&longitude={lon}"
    "&current=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m,is_day"
    "&daily=weather_code,temperature_2m_max,temperature_2m_min"
    "&timezone=auto&forecast_days=7"
)


def fetch(url):
    with urllib.request.urlopen(url, timeout=10) as response:
        return json.load(response)


def resolve_location():
    if len(sys.argv) >= 3 and sys.argv[1] and sys.argv[2]:
        city = sys.argv[3] if len(sys.argv) > 3 else ""
        return sys.argv[1], sys.argv[2], city

    geo = fetch(GEO_URL)
    if geo.get("status") != "success":
        raise RuntimeError("no se pudo ubicar por IP")
    return geo["lat"], geo["lon"], geo.get("city", "")


def main():
    try:
        lat, lon, city = resolve_location()
        data = fetch(FORECAST_URL.format(lat=lat, lon=lon))
        current, daily = data["current"], data["daily"]
        print(json.dumps({
            "city": city,
            "temp": current["temperature_2m"],
            "code": current["weather_code"],
            "humidity": current["relative_humidity_2m"],
            "wind": current["wind_speed_10m"],
            "isDay": current["is_day"],
            "days": [
                {"date": date, "code": code, "max": high, "min": low}
                for date, code, high, low in zip(
                    daily["time"],
                    daily["weather_code"],
                    daily["temperature_2m_max"],
                    daily["temperature_2m_min"],
                )
            ],
        }))
    except Exception as exc:  # network, DNS, malformed payload
        print(json.dumps({"error": str(exc) or exc.__class__.__name__}))


main()
