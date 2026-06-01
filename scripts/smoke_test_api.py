import json
import sys
import time
import urllib.error
import urllib.request


BASE_URL = "http://localhost:8000"


def request_json(
    method: str,
    path: str,
    data: dict | None = None,
    token: str | None = None,
):
    body = None
    headers = {}
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=body,
        headers=headers,
        method=method,
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload = resp.read().decode("utf-8")
        if payload:
            return json.loads(payload)
        return None


def main():
    try:
        health = None
        for _ in range(10):
            try:
                health = request_json("GET", "/health")
                break
            except Exception:
                time.sleep(1)
        if health is None:
            raise RuntimeError("API is not ready yet")
        if health.get("status") != "ok":
            raise RuntimeError("API healthcheck failed")

        user = request_json(
            "POST",
            "/register",
            {"email": f"smoke_{int(time.time())}@example.com", "password": "test1234"},
        )
        token = user.get("access_token")
        if not user.get("id") or not user.get("email") or user.get("role") != "client" or not token:
            raise RuntimeError("Registration response is invalid")

        login_user = request_json(
            "POST",
            "/login",
            {"email": user["email"], "password": "test1234"},
        )
        if login_user.get("email") != user["email"] or not login_user.get("access_token"):
            raise RuntimeError("Login response is invalid")

        services = request_json("GET", "/services")
        if not services:
            raise RuntimeError("No services returned")

        car = request_json(
            "POST",
            "/cars",
            {"brand": "Smoke Test Car", "number": "T 001 ST", "note": "created by smoke test"},
            token=token,
        )
        car_id = car["id"]

        booking = request_json(
            "POST",
            "/bookings",
            {
                "car_id": car_id,
                "service_ids": [services[0]["id"]],
                "complaint": "smoke test complaint",
            },
            token=token,
        )

        cars = request_json("GET", "/cars", token=token)
        bookings = request_json("GET", "/bookings", token=token)
        if not any(item["id"] == car_id for item in cars):
            raise RuntimeError("Created car not found in /cars")
        if not any(item["id"] == booking["id"] for item in bookings):
            raise RuntimeError("Created booking not found in /bookings")

        print("SMOKE TEST OK")
        print(f"user_id={user['id']}, car_id={car_id}, booking_id={booking['id']}")
    except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, KeyError, Exception) as exc:
        print(f"SMOKE TEST FAILED: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
