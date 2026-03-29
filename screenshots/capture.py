#!/usr/bin/env python3
"""Capture screenshots of all app screens using Chrome headless."""

import subprocess
import os
import time

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BASE = "http://localhost:4000"
OUT = os.path.dirname(os.path.abspath(__file__))

def screenshot(url, filename, width=1280, height=900):
    outpath = os.path.join(OUT, filename)
    cmd = [
        CHROME,
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--disable-web-security",
        "--hide-scrollbars",
        f"--screenshot={outpath}",
        f"--window-size={width},{height}",
        url
    ]
    try:
        subprocess.run(cmd, timeout=30, capture_output=True)
        if os.path.exists(outpath):
            size = os.path.getsize(outpath)
            print(f"  OK: {filename} ({size:,} bytes)")
            return True
        else:
            print(f"  FAIL: {filename} — no file created")
            return False
    except Exception as e:
        print(f"  FAIL: {filename} — {e}")
        return False

def main():
    print("Capturing screenshots...\n")

    # Public pages
    print("--- Public Pages ---")
    screenshot(f"{BASE}/", "01_landing.png", 1280, 2000)
    screenshot(f"{BASE}/book", "02_booking_step1.png", 1280, 1000)
    screenshot(f"{BASE}/sign-in", "03_signin.png", 1280, 800)
    screenshot(f"{BASE}/book/success", "04_payment_success.png", 1280, 600)
    screenshot(f"{BASE}/book/cancel", "05_payment_cancel.png", 1280, 600)

    # Customer pages (dev_routes bypasses auth)
    print("\n--- Customer Pages ---")
    screenshot(f"{BASE}/appointments", "06_appointments.png", 1280, 1000)
    # We can't easily get a specific appointment ID, but we can try
    screenshot(f"{BASE}/appointments", "06b_appointments_detail.png", 390, 844)  # mobile view

    # Technician pages
    print("\n--- Technician Pages ---")
    screenshot(f"{BASE}/tech", "07_tech_dashboard.png", 390, 844)  # mobile-first
    screenshot(f"{BASE}/tech", "07b_tech_dashboard_desktop.png", 1280, 1000)

    # Admin pages
    print("\n--- Admin Pages ---")
    screenshot(f"{BASE}/admin/dispatch", "08_dispatch.png", 1280, 1200)
    screenshot(f"{BASE}/admin/metrics", "09_metrics.png", 1280, 1800)
    screenshot(f"{BASE}/admin/events", "10_events.png", 1280, 1000)
    screenshot(f"{BASE}/admin/formation", "11_formation.png", 1280, 1600)
    screenshot(f"{BASE}/admin/org-chart", "12_org_chart.png", 1280, 1000)
    screenshot(f"{BASE}/admin/procedures", "13_procedures.png", 1280, 1400)

    print(f"\nDone! Screenshots saved to {OUT}/")

if __name__ == "__main__":
    main()
