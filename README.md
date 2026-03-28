# Mobile Car Wash

A mobile car wash booking platform built as an E-Myth franchise prototype. Veteran-owned, built with Elixir/Phoenix/Ash, with real-time tracking, Stripe payments, and validated learning metrics.

## Tech Stack

- **Elixir 1.18** / **Phoenix 1.8** / **Ash Framework 3.21**
- **PostgreSQL 16** / **DaisyUI** / **Tailwind CSS**
- **Stripe Checkout** / **Oban** background jobs / **Swoosh** email
- **Phoenix PubSub** for real-time updates

## Quick Start

```bash
# Install dependencies
asdf install          # Erlang 27 + Elixir 1.18
brew services start postgresql@16

# Setup project
mix setup             # deps, database, migrations, seeds

# Start server
mix phx.server        # http://localhost:4000
```

## Demo Accounts

| Role | Email | Password | Home Page |
|------|-------|----------|-----------|
| Customer | customer@demo.com | Password123! | `/` |
| Technician | tech@demo.com | Password123! | `/tech` |
| Admin | admin@mobilecarwash.com | Password123! | `/admin/dispatch` |

---

## Application Screens

### Customer Experience

#### Landing Page (`/`)

The customer's first impression — hero section with value proposition, service cards, and subscription plans.

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│         Professional Car Wash at Your Door           │
│                                                      │
│   Skip the drive. We bring the full car wash         │
│   experience to your home, office, or anywhere       │
│   you park. Veteran-owned. Satisfaction guaranteed.  │
│                                                      │
│                 [ View Services ]                     │
│                                                      │
├──────────────────────────────────────────────────────┤
│                   Our Services                       │
│                                                      │
│  ┌─────────────────┐    ┌─────────────────┐         │
│  │  Basic Wash      │    │  Deep Clean      │         │
│  │  $50  · 45 min   │    │  $200 · 120 min  │         │
│  │  Exterior hand    │    │  Full interior    │         │
│  │  wash, tires,     │    │  + exterior with  │         │
│  │  windows, dry     │    │  clay bar, wax    │         │
│  │                   │    │                   │         │
│  │  [ Book Now ]     │    │  [ Book Now ]     │         │
│  └─────────────────┘    └─────────────────┘         │
├──────────────────────────────────────────────────────┤
│              How It Works                            │
│   1. Choose Your Service                             │
│   2. Pick a Time                                     │
│   3. We Come to You                                  │
├──────────────────────────────────────────────────────┤
│              Monthly Plans                           │
│                                                      │
│  Basic $90/mo    Standard $125/mo   Premium $200/mo  │
│  2 washes        4 washes           3 basic + 1 deep │
│  25% off deep    30% off deep       50% off deep     │
│  [Coming Soon]   [Coming Soon]      [Coming Soon]    │
│                  ★ Most Popular                      │
├──────────────────────────────────────────────────────┤
│       Proudly veteran-owned and operated             │
│  100% disabled veteran-owned small business          │
└──────────────────────────────────────────────────────┘
```

#### Booking Flow (`/book`)

7-step wizard: Service → Account → Vehicle → Address → Schedule → Review → Payment

```
┌──────────────────────────────────────────────────────┐
│  ● ─ ○ ─ ○ ─ ○ ─ ○ ─ ○ ─ ○                         │
│  1   2   3   4   5   6   7                           │
│                                                      │
│  Choose Your Service                                 │
│                                                      │
│  ┌─────────────────┐    ┌─────────────────┐         │
│  │ ▸ Basic Wash     │    │  Deep Clean      │         │
│  │   $50 · 45 min   │    │  $200 · 120 min  │         │
│  └─────────────────┘    └─────────────────┘         │
│                                                      │
│                              [ Continue ]            │
└──────────────────────────────────────────────────────┘
```

The Basic Wash card has an orange selection border. Each subsequent step collects vehicle info, address, preferred time slot, then shows a review summary before redirecting to Stripe Checkout.

#### My Appointments (`/appointments`)

Customer's appointment list with live tracking and photo upload:

```
┌──────────────────────────────────────────────────────┐
│  My Appointments                                     │
│                                                      │
│  ┌──────────────────────────────────────────┐       │
│  │  Basic Wash                    Confirmed  │       │
│  │  April 05, 2026 at 10:00 AM              │       │
│  │                                           │       │
│  │  [Track Live]  [+ Problem Area Photos]    │       │
│  └──────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────┘
```

- **Track Live** — opens the real-time progress page
- **+ Problem Area Photos** — upload photos with captions showing areas needing extra attention

#### Real-Time Tracking (`/appointments/:id/status`)

Live progress as the technician works — updates via PubSub, no refresh needed:

```
┌──────────────────────────────────────────────────────┐
│  Appointment Status                                  │
│  Basic Wash · April 05 at 10:00 AM                   │
│                                                      │
│  ┌────────────────────────────────────────┐          │
│  │  Appointment confirmed — we'll be there!│          │
│  │  Estimated time remaining: ~39 minutes  │          │
│  └────────────────────────────────────────┘          │
│                                                      │
│  Progress                                            │
│  ✅ 1. Vehicle Inspection          0:32              │
│  ⚪ 2. Pre-Rinse                   ~5m               │
│  ⚪ 3. Apply Soap                  ~3m               │
│  ⚪ 4. Hand Wash / Scrub           ~10m              │
│  ⚪ 5. Rinse                       ~5m               │
│  ⚪ 6. Tire & Wheel Cleaning       ~5m               │
│  ⚪ 7. Dry                         ~8m               │
│  ⚪ 8. Final Inspection            ~3m               │
│                                                      │
│  ████░░░░░░░░░░  1/8 steps · ~39 min remaining      │
│                                                      │
│  Service: Basic Wash                                 │
│  Location: 456 Oak Ave, Austin                       │
│  Status: [Confirmed]                                 │
└──────────────────────────────────────────────────────┘
```

Green circles = completed (with actual time). Pulsing yellow = in progress. Gray = pending (with estimate). The progress bar and ETA update in real-time as the technician completes each step.

---

### Technician Experience

#### Tech Dashboard (`/tech`)

Mobile-first daily schedule showing assigned appointments:

```
┌──────────────────────────────────────────────────────┐
│  My Schedule                                         │
│  Welcome, Owner                                      │
│                                                      │
│  ⓘ 3 unassigned appointment(s) — check dispatch     │
│                                                      │
│  Today                                               │
│  ┌──────────────────────────────────────────┐       │
│  │  Basic Wash              Confirmed        │       │
│  │  10:00 AM                                 │       │
│  │  Jane Customer                            │       │
│  │  456 Oak Ave, Austin                      │       │
│  │  ████████░░░░░  5/8 steps                 │       │
│  │  [ Continue Checklist ]                   │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  Tomorrow                                            │
│  No appointments tomorrow                            │
└──────────────────────────────────────────────────────┘
```

#### Wash Checklist (`/tech/checklist/:id`)

Interactive checklist with live timers — the E-Myth system in action:

```
┌──────────────────────────────────────────────────────┐
│  Wash Checklist                             [1/8]    │
│  ████░░░░░░░░░░░░░░  13.0% complete  ETA: ~39 min   │
│                                                      │
│  [ Take BEFORE Photo ]                               │
│                                                      │
│  ┌──────────────────────────────────────────┐       │
│  │ ✅ Vehicle Inspection              [Req]  │       │
│  │    Walk around vehicle. Note damage...    │       │
│  │    Actual: 00:32 / Est: 3 min  ✓ under   │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  ┌──────────────────────────────────────────┐       │
│  │ 2  Pre-Rinse                       [Req]  │  ◄── Active step
│  │    Rinse with deionized water...          │
│  │    🟢 01:45 / 5:00 est                    │  ◄── GREEN timer
│  │    ████░░░░░░░░░░░  (progress bar)        │
│  │                     [Done ✓]  [+ Photo]   │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  ┌──────────────────────────────────────────┐       │
│  │ 3  Apply Soap                      [Req]  │
│  │    Apply soap using foam cannon...        │
│  │                     [Start Step] [+ Photo]│
│  └──────────────────────────────────────────┘       │
│  ...                                                 │
│                                                      │
│  (on completion:)                                    │
│  ┌─ Time Analysis ──────────────────────────┐       │
│  │ Vehicle Inspection    00:32 / 3m   ✓      │       │
│  │ Pre-Rinse             04:10 / 5m   ✓      │       │
│  │ Apply Soap            03:30 / 3m   ✗ over │       │
│  │ ...                                       │       │
│  │ Total                 38:15               │       │
│  └───────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────┘
```

**Timer colors:**
- 🟢 **Green** — within estimated time
- 🟡 **Yellow** — 45 seconds remaining
- 🔴 **Red** — over the estimated time

Use the Time Analysis to identify where to optimize your SOPs.

---

### Admin / Manager Experience

#### Dispatch Center (`/admin/dispatch`)

The daily operations command center — assign techs, monitor active washes:

```
┌──────────────────────────────────────────────────────┐
│  Dispatch Center            Sunday, March 29, 2026   │
│                                       [03/29/2026 📅]│
│                                                      │
│  🔴 3 Unassigned                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │Basic Wash│  │Deep Clean│  │Basic Wash│          │
│  │10:00 AM  │  │01:00 PM  │  │04:00 PM  │          │
│  │Confirmed │  │Confirmed │  │Pending   │          │
│  │Jane C.   │  │Jane C.   │  │Jane C.   │          │
│  │[Owner ▾] │  │[Assign ▾]│  │[Assign ▾]│          │
│  └──────────┘  └──────────┘  └──────────┘          │
│                                                      │
│  🟢 Active Washes                                    │
│  ┌──────────────────────────────────────────┐       │
│  │ Tech: Owner · Basic Wash · 10:00 AM      │       │
│  │ Customer: Jane Customer                   │       │
│  │ ████████░░░░  5/8 steps   ETA: 16 min    │       │
│  │ Current: Rinse                            │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  Schedule                                            │
│  ┌─ Owner ──────────────────────────────────┐       │
│  │ 10:00 AM  Basic Wash  Jane C.  ✓ Done    │       │
│  │ 11:30 AM  Deep Clean  Jane C.  🔵 Conf   │       │
│  └──────────────────────────────────────────┘       │
│  ┌─ Unassigned ─────────────────────────────┐       │
│  │ 04:00 PM  Basic Wash  Jane C.  ⚪ Pend   │       │
│  └──────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────┘
```

Active wash progress bars update in **real-time** via PubSub as technicians check off steps.

#### Metrics Dashboard (`/admin/metrics`)

The validated learning engine — Build → Measure → Learn:

```
┌──────────────────────────────────────────────────────┐
│  Metrics Dashboard                  [Last 7 Days ▾]  │
│  Build → Measure → Learn            [Event Explorer] │
│                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │Revenue   │ │Subscribers│ │Bookings  │ │Convert.│ │
│  │ $0       │ │ 0         │ │ 0        │ │ 0.0%   │ │
│  │0 payments│ │ all time  │ │last 7 day│ │visit→bk│ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ │
│                                                      │
│  AARRR Funnel              Daily Revenue             │
│  Visitors    ████████ 13   No revenue data           │
│  Signups           ░ 0                               │
│  Bk Started  ██████ 14                               │
│  Bk Complete       ░ 0                               │
│  Payments          ░ 0                               │
│  Returning         ░ 0                               │
│                                                      │
│  Pivot Signals                                       │
│  ✗ Weekly Traffic   13 visitors  (≥50)  → Pivot mktg │
│  ✗ Visit→Signup     0.0%        (≥5%)  → Pivot LP   │
│  ✗ Signup→Booking   0.0%        (≥30%) → Reduce UX  │
│  ✗ Abandonment      100%        (≤60%) → Fix payment│
│  ✓ Monthly Churn    0.0%        (≤15%) → On track   │
│                                                      │
│  Recent Events                      [View All →]     │
│  21:55  booking.started  sess_9BI  service=basic_w   │
│  21:54  page.viewed      sess_V28  page=landing      │
│  21:54  page.viewed      sess_2RD  page=landing      │
└──────────────────────────────────────────────────────┘
```

Red signals tell you exactly when to pivot and what to change.

#### Event Explorer (`/admin/events`)

Paginated stream of every analytics event:

```
┌──────────────────────────────────────────────────────┐
│  Event Explorer                      [← Dashboard]  │
│  28 total events         [All Events ▾]              │
│                                                      │
│  Time      Event              Session    Properties  │
│  21:55:55  booking.started    sess_9BI   service=bw  │
│  21:54:55  page.viewed        sess_V28   page=land   │
│  21:54:53  page.viewed        sess_2RD   page=land   │
│  19:44:16  booking.started    sess_N34   service=bw  │
│  19:44:07  booking.started    sess_02d   service=    │
│  19:39:54  booking.started    sess_5Kc   service=dc  │
│  ...                                                 │
│                                                      │
│  [← Previous]       Page 1        [Next →]           │
└──────────────────────────────────────────────────────┘
```

Filter by event type (page.viewed, booking.started, etc.) to debug customer behavior.

#### Business Formation (`/admin/formation`)

Track every TX state, federal, and veteran certification task:

```
┌──────────────────────────────────────────────────────┐
│  Business Formation        [← Dashboard]             │
│  TX State · Federal · Veteran Certs · Compliance     │
│                                                      │
│  Total: 22  Completed: 0  Progress: 0%  Overdue: 0  │
│  [All Categories ▾]  [All Statuses ▾]                │
│                                                      │
│  Texas State Formation                               │
│  ┌──────────────────────────────────────────┐       │
│  │ TX Sales Tax Permit     Not Started  high │       │
│  │ Apply for TX Sales...   [Gov website →]   │       │
│  │                     [Not Started ▾] [✓]   │       │
│  ├──────────────────────────────────────────┤       │
│  │ LLC Filing with TX SOS  Not Started  high │       │
│  │ File Certificate of...  [Gov website →]   │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  Compliance & Renewals                               │
│  ┌──────────────────────────────────────────┐       │
│  │ Quarterly Sales Tax    Jul 20, 2026  high │       │
│  │ Filing                 ◌ recurring        │       │
│  ├──────────────────────────────────────────┤       │
│  │ Annual TX Franchise    May 15, 2027  high │       │
│  │ Tax Report             ◌ recurring        │       │
│  └──────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────┘
```

Completing a recurring task auto-creates the next one (e.g., next year's franchise tax report).

#### Org Chart (`/admin/org-chart`)

E-Myth franchise prototype — every position defined:

```
┌──────────────────────────────────────────────────────┐
│  Organization Chart           [SOPs]  [Dashboard]    │
│  E-Myth franchise prototype — every position defined │
│                                                      │
│                  ┌──────────────┐                    │
│                  │  Owner / CEO │                    │
│                  │  Level 0     │                    │
│                  └──────┬───────┘                    │
│              ┌──────────┴──────────┐                 │
│     ┌────────┴────────┐  ┌────────┴────────┐        │
│     │ Ops Manager     │  │ Admin Assistant │        │
│     │ Level 1         │  │ Level 1         │        │
│     └────────┬────────┘  └─────────────────┘        │
│       ┌──────┴──────┐                                │
│  ┌────┴────┐  ┌─────┴────┐                          │
│  │Lead Tech│  │Technician│                          │
│  │Level 2  │  │Level 2   │                          │
│  └─────────┘  └──────────┘                          │
│                                                      │
│  "Build it as if you're going to franchise 5,000."  │
└──────────────────────────────────────────────────────┘
```

#### Standard Operating Procedures (`/admin/procedures`)

The systems that run the business:

```
┌──────────────────────────────────────────────────────┐
│  Standard Operating Procedures  [Org Chart][Dashboard]│
│  The systems that run the business                   │
│                                                      │
│  ┌──────────────────────────────────────────┐       │
│  │  Basic Wash Procedure    8 steps  ~42 min │       │
│  │  Standard operating procedure for a       │       │
│  │  basic exterior wash.    [View Steps]     │       │
│  │                                           │       │
│  │  #  Step                   Time  Required │       │
│  │  1  Vehicle Inspection     3 min  ✓       │       │
│  │  2  Pre-Rinse              5 min  ✓       │       │
│  │  3  Apply Soap             3 min  ✓       │       │
│  │  4  Hand Wash / Scrub     10 min  ✓       │       │
│  │  5  Rinse                  5 min  ✓       │       │
│  │  6  Tire & Wheel Cleaning  5 min  ✓       │       │
│  │  7  Dry                    8 min  ✓       │       │
│  │  8  Final Inspection       3 min  ✓       │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  ┌──────────────────────────────────────────┐       │
│  │  Deep Clean & Detail    15 steps ~135 min │       │
│  │  Full interior + exterior with clay bar,  │       │
│  │  wax, and full interior treatment.        │       │
│  │                          [View Steps]     │       │
│  └──────────────────────────────────────────┘       │
│                                                      │
│  E-Myth Principle: The system is the solution.       │
└──────────────────────────────────────────────────────┘
```

#### Sign In (`/sign-in`)

Role-based login — each role redirects to their home page:

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│              Email                                   │
│              [ _________________________ ]            │
│                                                      │
│              Password                                │
│              [ _________________________ ]            │
│                                                      │
│              Need an account?                        │
│                                                      │
│              [         Sign in          ]            │
│                                                      │
└──────────────────────────────────────────────────────┘
```

- Customer login → redirects to `/`
- Technician login → redirects to `/tech`
- Admin login → redirects to `/admin/dispatch`

---

## All Routes

| Route | Auth | Description |
|-------|------|-------------|
| `/` | Public | Landing page — services, plans, veteran badge |
| `/book` | Public | 7-step booking wizard |
| `/sign-in` | Public | Login (role-based redirect) |
| `/book/success` | Public | Post-payment confirmation |
| `/book/cancel` | Public | Payment cancelled, retry option |
| `/appointments` | Customer | My appointments with tracking links |
| `/appointments/:id/status` | Customer | Real-time wash progress (PubSub) |
| `/tech` | Technician | Daily schedule + assignment list |
| `/tech/checklist/:id` | Technician | Interactive checklist with timers |
| `/admin/dispatch` | Admin | Technician assignment + live progress |
| `/admin/metrics` | Admin | AARRR funnel, pivot signals, KPIs |
| `/admin/events` | Admin | Analytics event explorer |
| `/admin/formation` | Admin | Business formation task tracker |
| `/admin/org-chart` | Admin | E-Myth organizational hierarchy |
| `/admin/procedures` | Admin | Standard operating procedures |
| `/dev/dashboard` | Dev | Phoenix LiveDashboard |
| `/dev/mailbox` | Dev | Email preview (Swoosh) |

## Architecture

- **8 Ash Domains**: Accounts, Fleet, Scheduling, Billing, Analytics, Audit, Operations, Compliance
- **25 Ash Resources** with PostgreSQL data layer
- **Real-time**: Phoenix PubSub for appointment tracking (no polling)
- **Payments**: Stripe Checkout with webhook handling
- **Background Jobs**: Oban with notification, billing, and analytics queues
- **Email**: Swoosh with booking confirmations and deadline reminders
- **Security**: CSP headers, CSRF, rate limiting, PII encryption ready

## Testing

```bash
mix test    # 55 tests, 0 failures
```
