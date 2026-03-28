# Mobile Car Wash — User Guide

## Overview

This application serves three types of users, each with a tailored experience:

| Role | Login | Home Page | Key Features |
|------|-------|-----------|-------------|
| **Customer** | customer@demo.com | `/` | Book washes, upload problem photos, track progress in real-time |
| **Technician** | tech@demo.com | `/tech` | View assigned appointments, run checklists with timers, upload before/after photos |
| **Admin/Manager** | admin@mobilecarwash.com | `/admin/dispatch` | Assign technicians, monitor active washes, view metrics, manage formation tasks |

**All demo passwords:** `Password123!`

---

## 1. Customer Experience

### 1.1 Landing Page (`/`)

The first thing customers see — your value proposition, services, and pricing.

**Hero Section:**
- "Professional Car Wash at Your Door"
- Veteran-owned tagline
- "View Services" call-to-action

**Service Cards:**
- **Basic Wash** — $50, 45 minutes, exterior hand wash
- **Deep Clean & Detail** — $200, 120 minutes, full interior + exterior

Each card has a "Book Now" button that starts the booking flow.

**Monthly Plans:**
- **Basic** — $90/mo: 2 basic washes + 25% off deep cleans
- **Standard** — $125/mo: 4 basic washes + 30% off deep cleans (Most Popular)
- **Premium** — $200/mo: 3 basic + 1 deep clean + 50% off additional

**Footer:**
- "Proudly veteran-owned and operated"
- "100% disabled veteran-owned small business"

### 1.2 Booking Flow (`/book`)

A 7-step wizard that guides customers through scheduling a wash:

**Step 1 — Choose Service:**
- Service cards with prices and duration
- Pre-selectable via URL (e.g., `/book?service=basic_wash`)
- Step indicator shows progress (1-7)

**Step 2 — Account:**
- Sign in or create an account
- Skipped automatically if already logged in

**Step 3 — Vehicle:**
- Select an existing vehicle or add a new one
- Fields: Make, Model, Year, Color, Size (Sedan/SUV/Truck/Van)

**Step 4 — Address:**
- Select a saved address or enter a new one
- Fields: Street, City, State (default TX), ZIP

**Step 5 — Schedule:**
- Date picker (tomorrow onward)
- Time slot grid showing available slots
- Business hours: 8am-6pm, Monday-Saturday

**Step 6 — Review:**
- Summary of all selections: service, vehicle, address, date/time, price
- "Confirm Booking" button

**Step 7 — Payment:**
- Redirects to Stripe Checkout for secure payment
- Returns to success or cancel page

### 1.3 My Appointments (`/appointments`)

After booking, customers can view their appointments:

- **Appointment cards** showing service name, date/time, status badge
- **Track Live** button — opens real-time tracking page
- **+ Problem Area Photos** — upload photos of areas needing extra attention (with captions)

### 1.4 Real-Time Tracking (`/appointments/:id/status`)

While the technician works, customers see live progress:

- **Status banner** — "Appointment confirmed", "Wash in progress", "Complete!"
- **Step-by-step progress list:**
  - Green circle + checkmark: completed steps (with actual time)
  - Pulsing yellow circle: step currently in progress
  - Gray circle: pending steps (with estimated time)
- **Overall progress bar** with steps done/total and ETA
- **Before/after photo gallery** — appears as technician uploads photos
- **Updates in real-time** via PubSub — no page refresh needed

### 1.5 Payment Pages

- **Success** (`/book/success`) — "Payment Successful!" with booking details
- **Cancelled** (`/book/cancel`) — "Payment Cancelled" with Try Again button

---

## 2. Technician Experience

### 2.1 Tech Dashboard (`/tech`)

The technician's daily command center (mobile-friendly):

- **Today's appointments** — assigned to this technician
- **Tomorrow's appointments** — upcoming schedule
- **Unassigned count** — alert if appointments need assignment
- Each appointment shows: service, time, customer name, address, status
- **Start/Continue Checklist** button for each appointment

### 2.2 Wash Checklist (`/tech/checklist/:id`)

The interactive checklist with live timers — this is the E-Myth system in action:

**Header:**
- Progress: 0/8, 0.0% complete, ETA ~42 min
- Progress bar

**Before Photo:**
- "Take BEFORE Photo" banner at the top (before starting any steps)

**Customer Problem Areas:**
- If the customer uploaded problem area photos, they appear at the top
- Technician sees these before starting the wash

**Each Step Has:**
- Step number, title, description
- "Required" badge for mandatory steps
- **Start Step** button — begins the timer
- **+ Photo** button — document this step with a photo

**Timer System (active step):**
- Live countdown: `MM:SS` format
- Progress bar fills as time passes
- **Green** — within estimated time
- **Yellow** — 45 seconds remaining
- **Red** — over the estimated time
- **Done** button — completes the step, records actual time

**Completed Steps Show:**
- Green checkmark, title struck through
- **Actual time vs Estimated** (green if under, red if over)

**After Photo:**
- "Take AFTER Photo to Complete" banner when all required steps done

**Time Analysis (on completion):**
- Table showing actual vs estimated for every step
- Total actual time
- Use this data to optimize your SOPs

---

## 3. Admin/Manager Experience

### 3.1 Dispatch Center (`/admin/dispatch`)

The daily operations command center:

**Unassigned Section:**
- Red badge showing count of unassigned appointments
- Each card shows: service, time, customer, status
- **Assign Technician** dropdown on each card

**Active Washes:**
- Cards for appointments currently in progress
- **Real-time progress bar** with steps done/total and ETA
- **Current step name** displayed
- Updates via PubSub as technicians work

**Schedule by Technician:**
- Grouped timeline view per technician
- Shows all appointments with times and status badges
- "Unassigned" group for appointments without a tech

**Date Picker:**
- Navigate to any day's schedule

### 3.2 Metrics Dashboard (`/admin/metrics`)

The validated learning engine — Build, Measure, Learn:

**KPI Cards (top row):**
- Revenue (total from succeeded payments)
- Active Subscribers (count)
- Bookings (for selected period)
- Conversion Rate (visit → booking %)

**AARRR Funnel:**
- Visitors → Signups → Bookings Started → Completed → Payments → Returning
- Horizontal bar chart with percentages at each step

**Daily Revenue Chart:**
- Bar chart of daily revenue for the period

**Booking Flow Stats:**
- Started, Completed, Abandoned counts
- Abandonment rate percentage
- Completions by step (where do customers drop off?)

**Pivot Signals:**
- 5 key metrics with red/yellow/green status:
  - Weekly Traffic (≥50 visitors)
  - Visit → Signup (≥5%)
  - Signup → Booking (≥30%)
  - Booking Abandonment (≤60%)
  - Monthly Churn (≤15%)
- Red signals show recommended action ("Pivot marketing channel", etc.)

**Recent Events:**
- Last 10 events with timestamps, event names, session IDs

**Period Selector:**
- This Week, Last 7 Days, Last 30 Days
- Auto-refreshes every 60 seconds

### 3.3 Event Explorer (`/admin/events`)

Detailed view of all analytics events:

- Total event count
- Filter by event name (dropdown)
- Paginated table: Time, Event (color-coded badges), Session, Properties
- Useful for debugging customer behavior

### 3.4 Business Formation (`/admin/formation`)

Track business formation and compliance tasks:

**Progress Summary:**
- Total Tasks, Completed, Progress %, Overdue count

**Categories (with filters):**
- **Texas State Formation** — LLC filing, registered agent, sales tax permit, etc.
- **Federal Requirements** — EIN, taxes, bank account, insurance
- **Disabled Veteran Certifications** — VOSB, SDVOSB, TX HUB, tax exemptions
- **Compliance & Renewals** — Annual franchise tax, quarterly sales tax, insurance renewal

**Each Task Shows:**
- Name, description, gov website link
- Status badge (Not Started / In Progress / Completed / Blocked)
- Priority badge (High / Medium / Low)
- Due date with "recurring" badge for annual/quarterly tasks
- Status dropdown + Complete button
- Completing a recurring task auto-creates the next occurrence

### 3.5 Organization Chart (`/admin/org-chart`)

E-Myth franchise prototype organizational structure:

- **Visual hierarchy tree:**
  - Owner/CEO (Level 0)
  - Operations Manager + Admin Assistant (Level 1)
  - Lead Technician + Technician (Level 2)
- Position cards with descriptions and level badges
- Navigation to SOPs and Dashboard

### 3.6 Standard Operating Procedures (`/admin/procedures`)

The systems that run the business:

- **Basic Wash Procedure** — 8 steps, ~42 min
  1. Vehicle Inspection (3 min)
  2. Pre-Rinse (5 min)
  3. Apply Soap (3 min)
  4. Hand Wash / Scrub (10 min)
  5. Rinse (5 min)
  6. Tire & Wheel Cleaning (5 min)
  7. Dry (8 min)
  8. Final Inspection (3 min)

- **Deep Clean & Detail Procedure** — 15 steps, ~135 min
  - Full interior (vacuum, dashboard, leather, carpet, windows)
  - Full exterior (wash, clay bar, wax, tires)
  - Engine bay (optional)
  - Final inspection

Each step shows: number, title, description, estimated time, required/optional badge.

E-Myth quote: "The system is the solution."

---

## Quick Reference

### All Routes

| Route | Role | Purpose |
|-------|------|---------|
| `/` | Public | Landing page with services and plans |
| `/book` | Public | Multi-step booking wizard |
| `/sign-in` | Public | Login page |
| `/book/success` | Public | Post-payment success |
| `/book/cancel` | Public | Payment cancelled |
| `/appointments` | Customer | My appointments list |
| `/appointments/:id/status` | Customer | Real-time wash tracking |
| `/tech` | Technician | Today's schedule + assignments |
| `/tech/checklist/:id` | Technician | Interactive checklist with timers |
| `/admin/dispatch` | Admin | Dispatch center — assignments + live progress |
| `/admin/metrics` | Admin | AARRR metrics dashboard |
| `/admin/events` | Admin | Analytics event explorer |
| `/admin/formation` | Admin | Business formation tracking |
| `/admin/org-chart` | Admin | E-Myth org chart |
| `/admin/procedures` | Admin | Standard operating procedures |
| `/dev/dashboard` | Dev only | Phoenix LiveDashboard |
| `/dev/mailbox` | Dev only | Email preview (Swoosh) |

### Demo Credentials

| Role | Email | Password |
|------|-------|----------|
| Customer | customer@demo.com | Password123! |
| Technician | tech@demo.com | Password123! |
| Admin | admin@mobilecarwash.com | Password123! |
