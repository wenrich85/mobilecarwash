// Screenshot capture script using Chrome DevTools Protocol
// Usage: /Applications/Google\ Chrome.app/.../Google\ Chrome --headless --disable-gpu --run-all-compositor-stages-before-draw ...
// We'll use a simpler approach: node with Chrome's built-in fetch + screencapture

const { execSync } = require('child_process');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE = 'http://localhost:4000';
const OUT = __dirname;

// Chrome headless screenshot function
function screenshot(url, filename, width = 1280, height = 900) {
  const outPath = path.join(OUT, filename);
  try {
    execSync(
      `"${CHROME}" --headless=new --disable-gpu --screenshot="${outPath}" --window-size=${width},${height} --hide-scrollbars --default-background-color=0 "${url}"`,
      { timeout: 30000, stdio: 'pipe' }
    );
    console.log(`  OK: ${filename}`);
  } catch (e) {
    console.error(`  FAIL: ${filename} — ${e.message.slice(0, 100)}`);
  }
}

// For authenticated pages we need cookies. Let's get a session cookie first.
function getSessionCookie(email, password) {
  return new Promise((resolve, reject) => {
    // First, get the CSRF token from the sign-in page
    const getReq = http.get(`${BASE}/sign-in`, (res) => {
      let body = '';
      // Grab the set-cookie headers
      const cookies = (res.headers['set-cookie'] || []).map(c => c.split(';')[0]).join('; ');

      res.on('data', d => body += d);
      res.on('end', () => {
        // Find CSRF token
        const csrfMatch = body.match(/name="_csrf_token"[^>]*value="([^"]+)"/);
        if (!csrfMatch) {
          // Try the other format
          const altMatch = body.match(/csrf_token.*?value="([^"]+)"/s);
          if (!altMatch) {
            console.log('Could not find CSRF token, trying form post anyway...');
          }
        }
        const csrf = csrfMatch ? csrfMatch[1] : '';

        // POST to sign-in
        const postData = `customer[email]=${encodeURIComponent(email)}&customer[password]=${encodeURIComponent(password)}&_csrf_token=${encodeURIComponent(csrf)}`;

        const postReq = http.request(`${BASE}/auth/customer/password/sign_in`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Cookie': cookies
          }
        }, (postRes) => {
          const sessionCookies = (postRes.headers['set-cookie'] || []).map(c => c.split(';')[0]).join('; ');
          resolve(sessionCookies || cookies);
        });

        postReq.on('error', reject);
        postReq.write(postData);
        postReq.end();
      });
    });
    getReq.on('error', reject);
  });
}

async function main() {
  console.log('Taking screenshots...\n');

  // Public pages (no auth needed)
  console.log('--- Public Pages ---');
  screenshot(`${BASE}/`, '01_landing.png', 1280, 1600);
  screenshot(`${BASE}/book`, '02_booking_step1.png');
  screenshot(`${BASE}/sign-in`, '03_signin.png');
  screenshot(`${BASE}/book/success`, '04_payment_success.png');
  screenshot(`${BASE}/book/cancel`, '05_payment_cancel.png');

  // For authenticated pages, Chrome headless can't easily pass session cookies
  // Let's use a different approach: create a small HTML page that logs in via JS and navigates

  // Actually, Chrome headless supports --user-data-dir with pre-set cookies
  // Simpler: we'll use the dev routes bypass if available, or screenshot what we can

  // Let's check if dev routes are enabled (they should be in dev mode)
  console.log('\n--- Customer Pages (need auth) ---');
  screenshot(`${BASE}/appointments`, '06_appointments.png');

  console.log('\n--- Technician Pages (need auth) ---');
  screenshot(`${BASE}/tech`, '07_tech_dashboard.png');

  console.log('\n--- Admin Pages (need auth) ---');
  screenshot(`${BASE}/admin/dispatch`, '08_dispatch.png');
  screenshot(`${BASE}/admin/metrics`, '09_metrics.png');
  screenshot(`${BASE}/admin/events`, '10_events.png');
  screenshot(`${BASE}/admin/formation`, '11_formation.png');
  screenshot(`${BASE}/admin/org-chart`, '12_org_chart.png');
  screenshot(`${BASE}/admin/procedures`, '13_procedures.png');

  console.log('\nDone! Check screenshots/ directory.');
}

main().catch(console.error);
