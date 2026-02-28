import requests
import json
import sys
import os

# Mocking a request to check endpoint existence via 400 vs 404
# We don't need real auth for 404 vs 400 check usually if the path is wrong
# But 400 implies the path is found but params are missing/invalid.

BASE_URL = "https://app-api.pixiv.net"

endpoints = [
    "/v1/illust/series",
    "/v2/illust/series",
    "/v1/manga/series",
    "/v2/manga/series",
    "/v1/illust-series/detail",
]

headers = {
    "User-Agent": "PixivIOSApp/7.13.3 (iOS 14.6; iPhone13,2)",
    "App-OS": "ios",
    "App-OS-Version": "14.6",
}

def test_endpoint(path):
    url = f"{BASE_URL}{path}"
    try:
        # We use a dummy ID to trigger a potential 400/403 instead of 404
        response = requests.get(url, params={"illust_series_id": 1}, headers=headers, timeout=5)
        print(f"Path: {path} | Status: {response.status_code}")
        # Also try with 'series_id' which is used in novel_series
        response2 = requests.get(url, params={"series_id": 1}, headers=headers, timeout=5)
        print(f"Path: {path} (series_id) | Status: {response2.status_code}")
    except Exception as e:
        print(f"Path: {path} | Error: {e}")

if __name__ == "__main__":
    print("Testing Pixiv App API endpoints for series support...")
    for ep in endpoints:
        test_endpoint(ep)
