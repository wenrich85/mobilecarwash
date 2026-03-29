# Mobile Car Wash — Project Status

## Current State (March 29, 2026)

### By the Numbers
- **146 tests, 0 failures** — stable across multiple runs
- **12,500+ lines of code** across 91 Elixir source files
- **8 Ash domains** with 25+ resources
- **16 routes** across 4 role-scoped live sessions
- **30 git commits** of incremental, tested development
- **3 state machines** (booking flow, wash lifecycle, step sequencing)

### Tech Stack
- Elixir 1.18.4 / Erlang/OTP 27 / Phoenix 1.8.5 / Ash Framework 3.21
- PostgreSQL 16 / DaisyUI + Tailwind CSS
- Stripe Checkout / Oban background jobs / Swoosh email
- Phoenix PubSub for real-time updates

---

## What's Built

### Customer Experience
| Feature | Status | Route |
|---------|--------|-------|
| Landing page with services + plans | ✅ | `/` |
| 7-step booking wizard with state machine | ✅ | `/book` |
| Guest checkout (no account needed) | ✅ | `/book` step 2 |
| Vehicle-based pricing (Car 1.0x, SUV 1.2x, Pickup 1.5x) | ✅ | `/book` step 3 |
| Time slot availability (8am-6pm Mon-Sat) | ✅ | `/book` step 5 |
| Stripe Checkout payment | ✅ | → Stripe |
| My Appointments with photo upload | ✅ | `/appointments` |
| Real-time wash tracking via PubSub | ✅ | `/appointments/:id/status` |
| Booking state persists across reconnects (ETS cache) | ✅ | — |

### Technician Experience
| Feature | Status | Route |
|---------|--------|-------|
| Daily schedule (today + tomorrow) | ✅ | `/tech` |
| Start Wash → creates checklist from SOP | ✅ | `/tech` |
| Interactive checklist with step timers | ✅ | `/tech/checklist/:id` |
| Timer colors: green → yellow (45s left) → red (over) | ✅ | `/tech/checklist/:id` |
| Before/after photo uploads | ✅ | `/tech/checklist/:id` |
| Customer problem area photo display | ✅ | `/tech/checklist/:id` |
| Sequential step enforcement (state machine) | ✅ | — |
| Auto-complete wash when all required steps done | ✅ | — |
| Actual vs estimated time tracking | ✅ | — |
| Earnings summary (current pay period) | ✅ | `/tech` |
| Completed wash history | ✅ | `/tech` |
| Per-tech pay rate (configurable) | ✅ | — |
| Configurable pay period (Mon-Sun default) | ✅ | — |

### Admin / Manager Experience
| Feature | Status | Route |
|---------|--------|-------|
| Dispatch center with filters (date/status/tech) | ✅ | `/admin/dispatch` |
| Assign technicians to appointments | ✅ | `/admin/dispatch` |
| Confirm pending appointments | ✅ | `/admin/dispatch` |
| Real-time active wash progress bars | ✅ | `/admin/dispatch` |
| Manage technicians (add/link account/set rate) | ✅ | `/admin/dispatch` |
| AARRR funnel metrics dashboard | ✅ | `/admin/metrics` |
| Pivot signals (red/yellow/green thresholds) | ✅ | `/admin/metrics` |
| Analytics event explorer | ✅ | `/admin/events` |
| Business formation tracker (22 TX/federal/veteran tasks) | ✅ | `/admin/formation` |
| Recurring task auto-creation | ✅ | — |
| Deadline reminder emails (7-day + 1-day) | ✅ | — |
| E-Myth org chart (hierarchical) | ✅ | `/admin/org-chart` |
| Editable SOPs with drag-and-drop reordering | ✅ | `/admin/procedures` |
| Step CRUD (add/edit/delete/reorder) | ✅ | `/admin/procedures` |

### Infrastructure
| Feature | Status |
|---------|--------|
| Role-based auth (customer/technician/admin/guest) | ✅ |
| Session persistence across LiveView reconnects | ✅ |
| JWT token verification + token table storage | ✅ |
| Responsive DaisyUI navbar (role-aware) | ✅ |
| Stripe webhook handler with signature verification | ✅ |
| Email notifications (booking confirmation + reminder) | ✅ |
| Oban background jobs (notifications, billing, analytics) | ✅ |
| Event tracking (first-party analytics) | ✅ |
| Audit logging | ✅ |
| Booking state machine (pure functional, 32 tests) | ✅ |
| Wash state machine (pure functional, 21 tests) | ✅ |
| Session cache (ETS, survives reconnects) | ✅ |

---

## Suggestions for Future Development

### High Priority — Before Launch

1. **Subscription Billing (Stripe Subscriptions)**
   - Monthly plan sign-up via Stripe Customer Portal
   - Automatic billing, plan changes, cancellation
   - Usage tracking integration (washes used vs included)
   - Webhook handlers for subscription events

2. **Email Polish**
   - Configure production email provider (Mailgun/Postmark)
   - Branded HTML email templates
   - SMS notifications via Twilio (appointment reminders, wash started/complete)

3. **Deployment**
   - Fly.io or Railway deployment
   - Environment variables (STRIPE_SECRET_KEY, DATABASE_URL, etc.)
   - SSL certificate + custom domain
   - Production database (managed PostgreSQL)

4. **Sign-In UX**
   - Style the ash_authentication sign-in/register forms with DaisyUI
   - Password reset flow
   - "Remember me" checkbox

### Medium Priority — Post-Launch

5. **Route Optimization**
   - Map view showing today's appointments by location
   - Suggested route order to minimize drive time
   - Integration with Google Maps / Mapbox API for directions

6. **Customer Notifications**
   - "Technician is on the way" push notification
   - ETA based on distance + current appointment progress
   - Post-wash satisfaction survey (1-5 stars + optional comment)

7. **Reporting & Analytics**
   - Weekly/monthly revenue reports
   - Technician performance reports (avg time per wash, on-time %)
   - Customer retention cohort analysis
   - Export to CSV/PDF

8. **Inventory Tracking**
   - Track soap, wax, towels, etc. per van
   - Low-stock alerts
   - Cost per wash calculation

9. **Multi-Location / Territory Management**
   - Define service zones on a map
   - Route techs to appointments within their zone
   - Zone-based pricing adjustments

### Lower Priority — Growth Phase

10. **Native Mobile App**
    - iOS/Android app via JSON API v1 (routes already stubbed)
    - Push notifications
    - Offline checklist support for areas with poor connectivity

11. **Customer Portal**
    - Self-service subscription management
    - Wash history with before/after photo gallery
    - Referral program with tracking
    - Gift cards

12. **Fleet / Commercial Accounts**
    - Corporate accounts with multiple vehicles
    - Fleet pricing discounts
    - Centralized billing to company
    - Scheduled recurring washes

13. **Accounting Integration**
    - QuickBooks Online API integration
    - Automatic invoice creation
    - Expense tracking
    - Tax report generation

14. **Advanced E-Myth Systems**
    - Position contracts with linked SOPs
    - Training checklists for new hires
    - Quality scoring per technician per SOP step
    - SOP version history with change tracking

15. **Marketing Automation**
    - Automated follow-up emails (X days after wash)
    - Re-engagement campaigns for lapsed customers
    - Seasonal promotions
    - Google/Facebook ad integration with conversion tracking

---

## Demo Credentials

| Role | Email | Password |
|------|-------|----------|
| Customer | customer@demo.com | Password123! |
| Technician | tech@demo.com | Password123! |
| Admin | admin@mobilecarwash.com | Password123! |

## Quick Start

```bash
asdf install                    # Erlang 27 + Elixir 1.18
brew services start postgresql@16
mix setup                       # deps, DB, migrations, seeds
mix phx.server                  # http://localhost:4000
```
