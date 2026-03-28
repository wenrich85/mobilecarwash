# Mobile Car Wash Application — Master Plan

## Vision

A mobile-responsive web application for a mobile car wash business that allows customers to book one-time washes or subscribe to monthly plans. Built franchise-ready from day one using E-Myth Revisited principles. Solo operator at launch, architected for multi-crew scaling.

---

## System Architecture

```mermaid
graph TB
    subgraph "Client Layer"
        WEB[Phoenix LiveView<br/>Mobile-Responsive Web App]
        FUTURE_IOS[Future: iOS App]
        FUTURE_ANDROID[Future: Android App]
    end

    subgraph "API Layer"
        API[Phoenix JSON API<br/>versioned /api/v1]
    end

    subgraph "Application Layer"
        ASH[Ash Framework<br/>Resources & Domain Logic]
        AUTH[Authentication<br/>ash_authentication]
        AUTHZ[Authorization<br/>ash_authorization]
    end

    subgraph "Security Layer"
        RATE[Rate Limiting<br/>Hammer]
        CSRF[CSRF + CSP<br/>Phoenix built-in]
        ENCRYPT[PII Encryption<br/>Cloak.Ecto]
    end

    subgraph "Domain Contexts"
        BOOKING[Booking Context<br/>Services, Scheduling, Appointments]
        BILLING[Billing Context<br/>Subscriptions, Payments, Invoices]
        CUSTOMERS[Customer Context<br/>Profiles, Vehicles, Addresses]
        OPS[Operations Context<br/>Technicians, Vans, Zones]
    end

    subgraph "Learning Engine"
        EVENTS[Event Tracking<br/>Every user action]
        EXPERIMENTS[Experiment Framework<br/>A/B testing]
        AUDIT[Audit Log<br/>Every state change]
        METRICS[Metrics Dashboard<br/>AARRR Funnel + KPIs]
    end

    subgraph "Infrastructure"
        PG[(PostgreSQL)]
        MATVIEWS[Materialized Views<br/>Pre-aggregated metrics]
        STRIPE[Stripe API<br/>Payments & Subscriptions]
        OBAN[Oban<br/>Background Jobs]
        MAILER[Swoosh<br/>Email/SMS Notifications]
    end

    WEB --> API
    FUTURE_IOS -.-> API
    FUTURE_ANDROID -.-> API
    API --> ASH
    ASH --> AUTH
    ASH --> AUTHZ
    API --> RATE
    RATE --> CSRF
    CSRF --> ASH
    ASH --> BOOKING
    ASH --> BILLING
    ASH --> CUSTOMERS
    ASH --> OPS
    ASH --> EVENTS
    EVENTS --> EXPERIMENTS
    EVENTS --> METRICS
    BOOKING --> PG
    BILLING --> PG
    BILLING --> STRIPE
    CUSTOMERS --> ENCRYPT
    ENCRYPT --> PG
    OPS --> PG
    EVENTS --> PG
    AUDIT --> PG
    PG --> MATVIEWS
    MATVIEWS --> METRICS
    ASH --> OBAN
    ASH --> AUDIT
    OBAN --> MAILER
```

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Language | Elixir | Concurrency, fault tolerance, real-time via Phoenix |
| Web Framework | Phoenix 1.7+ / LiveView | Rich interactive UI without JS framework overhead |
| Domain Framework | Ash Framework | Declarative resources, built-in auth, API generation |
| Database | PostgreSQL | Robust, Ash-native support |
| Payments | **Stripe** | Best subscription/recurring billing APIs, strong Elixir library (`stripity_stripe`), handles SCA/PCI compliance |
| Background Jobs | Oban | Persistent job processing (reminders, billing, notifications) |
| Email/SMS | Swoosh + provider TBD | Confirmation emails, appointment reminders |
| Testing (BDD) | Wallaby + ExUnit | Browser-based BDD tests + unit/integration TDD |
| Testing (TDD) | ExUnit + Ash testing helpers | Resource-level and context-level tests |
| CSS | Tailwind CSS | Ships with Phoenix, mobile-first responsive |
| Deployment | Fly.io or self-hosted | Elixir-friendly, easy scaling |

---

## Domain Model

```mermaid
erDiagram
    CUSTOMER ||--o{ VEHICLE : owns
    CUSTOMER ||--o{ ADDRESS : has
    CUSTOMER ||--o| SUBSCRIPTION : subscribes_to
    CUSTOMER ||--o{ APPOINTMENT : books

    SUBSCRIPTION }o--|| SUBSCRIPTION_PLAN : references
    SUBSCRIPTION ||--o{ SUBSCRIPTION_USAGE : tracks

    APPOINTMENT }o--|| SERVICE_TYPE : for
    APPOINTMENT }o--|| VEHICLE : on
    APPOINTMENT }o--|| ADDRESS : at
    APPOINTMENT }o--o| TECHNICIAN : assigned_to

    TECHNICIAN }o--o| VAN : drives

    APPOINTMENT ||--o| PAYMENT : generates
    SUBSCRIPTION ||--o{ PAYMENT : generates

    CUSTOMER {
        uuid id PK
        string email
        string name
        string phone
        datetime created_at
    }

    VEHICLE {
        uuid id PK
        uuid customer_id FK
        string make
        string model
        integer year
        string color
        enum size "sedan, suv, truck, van"
    }

    ADDRESS {
        uuid id PK
        uuid customer_id FK
        string street
        string city
        string state
        string zip
        float latitude
        float longitude
        boolean is_default
    }

    SERVICE_TYPE {
        uuid id PK
        string name "basic_wash, deep_clean"
        integer base_price_cents
        integer duration_minutes
        text description
    }

    SUBSCRIPTION_PLAN {
        uuid id PK
        string name
        integer price_cents
        integer basic_washes_per_month
        integer deep_cleans_per_month
        integer deep_clean_discount_percent
        boolean active
    }

    SUBSCRIPTION {
        uuid id PK
        uuid customer_id FK
        uuid plan_id FK
        string stripe_subscription_id
        enum status "active, paused, cancelled"
        date current_period_start
        date current_period_end
    }

    SUBSCRIPTION_USAGE {
        uuid id PK
        uuid subscription_id FK
        date period_start
        integer basic_washes_used
        integer deep_cleans_used
    }

    APPOINTMENT {
        uuid id PK
        uuid customer_id FK
        uuid vehicle_id FK
        uuid address_id FK
        uuid service_type_id FK
        uuid technician_id FK
        datetime scheduled_at
        integer duration_minutes
        enum status "pending, confirmed, in_progress, completed, cancelled"
        integer price_cents
        integer discount_cents
        text notes
    }

    TECHNICIAN {
        uuid id PK
        string name
        string phone
        boolean active
    }

    VAN {
        uuid id PK
        string name
        string license_plate
        boolean active
    }

    PAYMENT {
        uuid id PK
        uuid customer_id FK
        uuid appointment_id FK
        uuid subscription_id FK
        string stripe_payment_intent_id
        integer amount_cents
        enum status "pending, succeeded, failed, refunded"
        datetime paid_at
    }
```

---

## Subscription Plans — Business Logic

```mermaid
graph LR
    subgraph "$90/mo — Basic"
        B1[2 Basic Washes]
        B2[25% off Deep Clean]
    end

    subgraph "$125/mo — Standard"
        S1[4 Basic Washes]
        S2[30% off Deep Clean]
    end

    subgraph "$200/mo — Premium"
        P1[3 Basic Washes]
        P2[1 Deep Clean included]
        P3[50% off additional Deep Clean]
    end

    subgraph "One-Time"
        O1[$50 Basic Wash]
        O2[$200 Deep Clean & Detail]
    end
```

---

## Customer Booking Flow

```mermaid
sequenceDiagram
    actor C as Customer
    participant W as Web App
    participant A as Ash Resources
    participant S as Stripe
    participant O as Oban Jobs

    C->>W: Visit landing page
    C->>W: Select service (one-time or subscription)
    C->>W: Sign up / Log in
    C->>W: Add vehicle & address
    C->>W: Pick date & time slot

    alt One-Time Wash
        W->>A: Create Appointment (pending)
        W->>S: Create PaymentIntent
        S-->>W: Client secret
        W->>C: Show payment form
        C->>W: Confirm payment
        W->>S: Confirm PaymentIntent
        S-->>W: Payment succeeded
        W->>A: Update Appointment (confirmed)
    else New Subscription
        W->>S: Create Subscription
        S-->>W: Subscription active
        W->>A: Create Subscription record
        W->>A: Create first Appointment
    else Existing Subscriber
        W->>A: Check usage this period
        A-->>W: Washes remaining
        W->>A: Create Appointment (auto-confirmed)
        W->>A: Increment usage
    end

    A->>O: Queue confirmation email
    A->>O: Queue reminder (24hr before)
    O-->>C: Email/SMS confirmation
```

---

## MVP Phased Delivery

```mermaid
gantt
    title MVP Build — April 2026 Go-Live
    dateFormat  YYYY-MM-DD
    axisFormat  %b %d

    section Phase 1 — Foundation + Security
    Project setup, Ash config, DB          :p1a, 2026-03-28, 2d
    Security baseline (CSP, CSRF, rate limit) :p1s, 2026-03-28, 1d
    Customer resource + auth               :p1b, after p1a, 2d
    Audit log + Event tracking resources   :p1e, after p1a, 1d
    Vehicle & Address resources            :p1c, after p1b, 1d
    Service types & seed data              :p1d, after p1b, 1d

    section Phase 2 — Booking Engine + Events
    Scheduling & availability logic        :p2a, after p1c, 2d
    Appointment resource & state machine   :p2b, after p2a, 2d
    Booking LiveView UI + event tracking   :p2c, after p2b, 2d

    section Phase 3 — Payments
    Stripe integration (one-time)          :p3a, after p2c, 2d
    Subscription plans & billing           :p3b, after p3a, 3d
    Usage tracking & discount logic        :p3c, after p3b, 2d

    section Phase 4 — Metrics + Polish + Launch
    Owner metrics dashboard (LiveView)     :p4m, after p3c, 2d
    Funnel views + experiment framework    :p4f, after p4m, 2d
    Landing page & marketing pages         :p4a, after p2c, 3d
    Email notifications (Oban + Swoosh)    :p4b, after p4f, 1d
    Mobile-responsive QA + security audit  :p4c, after p4b, 2d
    Deployment & go-live                   :p4d, after p4c, 1d
```

---

## Project Structure

```
mobile_car_wash/
├── lib/
│   ├── mobile_car_wash/
│   │   ├── accounts/           # Customer auth & profiles
│   │   │   ├── customer.ex     # Ash Resource
│   │   │   ├── token.ex        # Auth tokens
│   │   │   └── accounts.ex     # Ash Domain
│   │   ├── fleet/              # Vehicles, addresses
│   │   │   ├── vehicle.ex
│   │   │   ├── address.ex
│   │   │   └── fleet.ex        # Ash Domain
│   │   ├── scheduling/         # Appointments, availability
│   │   │   ├── appointment.ex
│   │   │   ├── service_type.ex
│   │   │   ├── time_slot.ex
│   │   │   └── scheduling.ex   # Ash Domain
│   │   ├── billing/            # Payments, subscriptions
│   │   │   ├── subscription_plan.ex
│   │   │   ├── subscription.ex
│   │   │   ├── subscription_usage.ex
│   │   │   ├── payment.ex
│   │   │   ├── stripe_client.ex
│   │   │   └── billing.ex      # Ash Domain
│   │   ├── analytics/          # Validated learning engine
│   │   │   ├── event.ex        # Ash Resource — all user events
│   │   │   ├── experiment.ex   # A/B test definitions
│   │   │   ├── experiment_assignment.ex
│   │   │   ├── funnel.ex       # Funnel calculation queries
│   │   │   ├── cohort.ex       # Cohort analysis queries
│   │   │   └── analytics.ex    # Ash Domain
│   │   ├── audit/              # Security audit trail
│   │   │   ├── audit_log.ex    # Ash Resource — all state changes
│   │   │   └── audit.ex        # Ash Domain
│   │   └── operations/         # Technicians, vans (Phase 2+)
│   │       ├── technician.ex
│   │       ├── van.ex
│   │       └── operations.ex   # Ash Domain
│   ├── mobile_car_wash_web/
│   │   ├── live/
│   │   │   ├── landing_live.ex
│   │   │   ├── booking_live.ex
│   │   │   ├── dashboard_live.ex
│   │   │   ├── subscription_live.ex
│   │   │   ├── admin/
│   │   │   │   ├── metrics_live.ex      # Owner dashboard — KPIs at a glance
│   │   │   │   ├── funnel_live.ex       # AARRR funnel visualization
│   │   │   │   ├── experiments_live.ex  # A/B test management
│   │   │   │   └── audit_live.ex        # Security audit log viewer
│   │   │   └── components/
│   │   ├── controllers/
│   │   │   └── api/v1/         # JSON API for future native apps
│   │   └── router.ex
│   └── mobile_car_wash.ex
├── test/
│   ├── mobile_car_wash/
│   │   ├── accounts_test.exs
│   │   ├── scheduling_test.exs
│   │   └── billing_test.exs
│   ├── mobile_car_wash_web/
│   │   └── live/
│   │       └── booking_live_test.exs
│   └── features/               # BDD feature tests (Wallaby)
│       ├── customer_signup_test.exs
│       ├── book_wash_test.exs
│       └── subscribe_test.exs
├── priv/
│   ├── repo/migrations/
│   └── static/
├── config/
├── mix.exs
└── .formatter.exs
```

---

## BDD/TDD Approach

```mermaid
graph TD
    BDD[Write BDD Feature Test<br/>Wallaby - describe user behavior] --> RED1[Run Test — RED]
    RED1 --> TDD[Write TDD Unit Test<br/>ExUnit - describe resource/function]
    TDD --> RED2[Run Test — RED]
    RED2 --> IMPL[Write Implementation<br/>Ash Resource / LiveView]
    IMPL --> GREEN[Run Unit Test — GREEN]
    GREEN --> CHECK{BDD test<br/>passes?}
    CHECK -->|No| TDD
    CHECK -->|Yes| REFACTOR[Refactor]
    REFACTOR --> NEXT[Next Feature]
```

**Example BDD cycle for booking:**

1. **BDD (outer loop):** Write a Wallaby test — "Customer visits site, selects basic wash, picks a time, pays, and sees confirmation"
2. **TDD (inner loop):** Write ExUnit tests for `Appointment.create/1`, `Billing.charge_one_time/2`, etc.
3. **Implement** Ash resources and LiveView to make tests green
4. **Refactor** and repeat

---

## Future Phases (Post-MVP)

```mermaid
graph TB
    MVP[Phase 1: MVP<br/>Customer Web App<br/>Booking + Payments] --> P2[Phase 2: Operations<br/>Multi-tech scheduling<br/>Route optimization<br/>Van management]
    P2 --> P3[Phase 3: E-Myth Systems<br/>Org charts<br/>Position descriptions<br/>SOPs & checklists]
    P3 --> P4[Phase 4: Business Admin<br/>TX formation tracking<br/>Federal compliance<br/>Veteran status benefits]
    P4 --> P5[Phase 5: Integrations<br/>Accounting software<br/>Gov APIs<br/>Marketing automation]
    P5 --> P6[Phase 6: Native Apps<br/>iOS & Android<br/>via JSON API v1]
```

---

## Security Architecture

```mermaid
graph TB
    subgraph "Edge Security"
        CF[Cloudflare / CDN<br/>DDoS protection, WAF]
        RATE[Rate Limiting<br/>Hammer library]
        CSP[Content Security Policy<br/>Phoenix CSP headers]
    end

    subgraph "Authentication & Authorization"
        AUTH_MW[ash_authentication<br/>Email + Magic Link + OAuth]
        AUTHZ_MW[ash_authorization<br/>Policy-based access control]
        SESS[Session Management<br/>Encrypted Phoenix sessions]
        MFA[Future: MFA / TOTP]
    end

    subgraph "Data Protection"
        ENCRYPT[Encryption at Rest<br/>Cloak + Ecto encrypted fields]
        PCI[PCI Compliance<br/>Stripe Elements — no card data touches server]
        HASH[Password Hashing<br/>Bcrypt via ash_authentication]
        AUDIT[Audit Log<br/>Every state change tracked]
    end

    subgraph "Input Validation"
        ASH_VAL[Ash Changeset Validations<br/>Type-safe, declarative]
        PARAM[Parameter Sanitization<br/>Phoenix strong params]
        CSRF[CSRF Protection<br/>Phoenix built-in tokens]
    end

    subgraph "API Security"
        API_AUTH[API Token Auth<br/>Bearer tokens for /api/v1]
        CORS[CORS Policy<br/>Whitelist origins]
        SCOPE[Scoped API Keys<br/>Read vs Write permissions]
    end

    CF --> RATE --> AUTH_MW
    AUTH_MW --> AUTHZ_MW
    AUTHZ_MW --> ASH_VAL
    ASH_VAL --> ENCRYPT
    ENCRYPT --> PCI
```

### Security Layers in Detail

| Layer | Implementation | Threat Mitigated |
|-------|---------------|-----------------|
| **DDoS / WAF** | Cloudflare free tier | Volumetric attacks, bot traffic |
| **Rate Limiting** | `Hammer` library — per-IP and per-user | Brute force login, API abuse |
| **CSRF** | Phoenix built-in CSRF tokens on all forms | Cross-site request forgery |
| **CSP Headers** | Strict Content-Security-Policy | XSS, script injection |
| **Authentication** | `ash_authentication` — email/password + magic link | Unauthorized access |
| **Authorization** | `ash_authorization` — policy per action per resource | Privilege escalation |
| **PCI Compliance** | Stripe Elements (client-side) — **zero card data on our server** | Card data breach |
| **Encryption at Rest** | `Cloak` + `Cloak.Ecto` for PII fields (email, phone, address) | Database breach |
| **Audit Logging** | Custom Ash change tracker — who, what, when, from where | Forensics, compliance |
| **Input Validation** | Ash changeset validations — type-safe, declarative | SQL injection, malformed data |
| **Session Security** | Encrypted cookies, short TTL, secure + httponly flags | Session hijacking |
| **API Auth** | Bearer token + scoped permissions | API abuse, data exfiltration |
| **Dependency Scanning** | `mix_audit` + `sobelow` in CI | Known vulnerabilities |

### Audit Log Schema

Every meaningful action is recorded — this feeds both security forensics AND the validated learning metrics:

```mermaid
erDiagram
    AUDIT_LOG {
        uuid id PK
        uuid actor_id FK "customer or system"
        string actor_type "customer, system, admin"
        string action "appointment.created, subscription.started, page.viewed"
        string resource_type "Appointment, Subscription, etc."
        uuid resource_id FK
        jsonb metadata "IP, user_agent, utm_params, variant, etc."
        jsonb changes "before/after diff"
        datetime inserted_at
    }

    EVENT {
        uuid id PK
        uuid customer_id FK "nullable — anonymous events"
        uuid session_id "anonymous session tracking"
        string event_name "landing.viewed, cta.clicked, booking.started, booking.completed"
        string source "web, api, email, sms"
        jsonb properties "page, referrer, utm_source, utm_medium, variant_id, etc."
        datetime inserted_at
    }

    EXPERIMENT {
        uuid id PK
        string name "pricing_page_v2, cta_color_test"
        string hypothesis "Showing social proof increases conversion by 15%"
        enum status "draft, running, concluded"
        jsonb variants "control: {}, treatment: {show_reviews: true}"
        datetime started_at
        datetime concluded_at
        jsonb results "conversion_rates, p_value, winner"
    }

    EXPERIMENT_ASSIGNMENT {
        uuid id PK
        uuid experiment_id FK
        uuid session_id "ties to EVENT.session_id"
        string variant "control, treatment_a, treatment_b"
        datetime assigned_at
    }

    EVENT }o--o| EXPERIMENT_ASSIGNMENT : correlated_via_session
    EXPERIMENT ||--o{ EXPERIMENT_ASSIGNMENT : has
    AUDIT_LOG }o--o| EVENT : correlated_by_actor
```

---

## Validated Learning & Actionable Metrics

This is the **Build → Measure → Learn** engine. Every feature ships with a hypothesis and a metric that tells us whether to **persevere, pivot, or kill**.

### The Innovation Accounting Framework

```mermaid
graph LR
    subgraph "BUILD"
        HYPO[State Hypothesis] --> FEAT[Build Minimum Feature]
        FEAT --> SHIP[Ship to Real Users]
    end

    subgraph "MEASURE"
        SHIP --> COLLECT[Collect Events<br/>via Event Tracking]
        COLLECT --> FUNNEL[Calculate Funnel Metrics]
        FUNNEL --> COHORT[Cohort Analysis]
    end

    subgraph "LEARN"
        COHORT --> DECIDE{Actionable<br/>Threshold Met?}
        DECIDE -->|Yes — Persevere| NEXT[Next Hypothesis]
        DECIDE -->|No — Pivot| PIVOT[Change Strategy]
        DECIDE -->|Inconclusive| EXTEND[Extend Experiment]
    end

    NEXT --> HYPO
    PIVOT --> HYPO
```

### The Metrics Dashboard — What You See at a Glance

```mermaid
graph TB
    subgraph "🔴 ACQUISITION — Are people finding us?"
        A1[Visitors / week]
        A2[Traffic source breakdown<br/>utm_source tracking]
        A3[Landing page → Signup<br/>conversion rate]
        A4[Cost per acquisition<br/>ad spend / signups]
    end

    subgraph "🟡 ACTIVATION — Are they booking?"
        B1[Signup → First Booking<br/>conversion rate]
        B2[Time to first booking<br/>hours/days from signup]
        B3[Booking abandonment rate<br/>started but not completed]
        B4[Service tier selection<br/>distribution]
    end

    subgraph "🟢 REVENUE — Are they paying?"
        C1[One-time revenue / week]
        C2[Subscription MRR<br/>monthly recurring revenue]
        C3[Average revenue per customer]
        C4[Subscription tier distribution]
    end

    subgraph "🔵 RETENTION — Are they coming back?"
        D1[Subscription churn rate<br/>monthly]
        D2[One-time → Subscription<br/>upgrade rate]
        D3[Rebooking rate<br/>2nd booking within 30 days]
        D4[Net Promoter Score<br/>post-wash survey]
    end

    subgraph "🟣 REFERRAL — Are they telling others?"
        E1[Referral signups<br/>via referral code]
        E2[Referral conversion rate]
        E3[Viral coefficient<br/>invites sent / signup]
    end
```

### Pirate Metrics (AARRR) — Mapped to Our Funnel

```mermaid
graph TD
    VISIT[Visit Landing Page] -->|"Acquisition Rate"| SIGNUP[Create Account]
    SIGNUP -->|"Activation Rate"| BOOK[Book First Wash]
    BOOK -->|"Revenue Conversion"| PAY[Complete Payment]
    PAY -->|"Retention Rate"| RETURN[Book Again / Subscribe]
    RETURN -->|"Referral Rate"| REFER[Refer a Friend]

    VISIT -.->|"Track: source, utm, device"| E1((Event))
    SIGNUP -.->|"Track: method, time_on_page"| E2((Event))
    BOOK -.->|"Track: service, tier, time_to_book"| E3((Event))
    PAY -.->|"Track: amount, method, discount"| E4((Event))
    RETURN -.->|"Track: days_since_last, plan_change"| E5((Event))
    REFER -.->|"Track: channel, referral_code"| E6((Event))
```

### Key Pivot Signals — When to Change Course

| Signal | Metric | Threshold | Action |
|--------|--------|-----------|--------|
| **Nobody's coming** | Weekly visitors | < 50 after 2 weeks marketing | Pivot marketing channel |
| **Coming but not signing up** | Visit → Signup rate | < 5% | Pivot landing page, value prop, or pricing display |
| **Signing up but not booking** | Signup → Booking rate | < 30% | Pivot UX, reduce friction, add urgency |
| **Booking but abandoning** | Booking abandonment | > 60% | Pivot payment flow, add trust signals |
| **Not coming back** | 30-day rebooking rate | < 20% for one-time | Pivot to subscription-first, improve service quality |
| **Subscriptions churning** | Monthly churn | > 15% | Pivot pricing tiers, add value, survey churned users |
| **Wrong tier chosen** | Tier distribution | > 70% on cheapest | Pivot pricing anchoring, reorder tiers |
| **One-time customers won't upgrade** | One-time → Sub rate | < 10% after 3 months | Pivot subscription value prop, trial period |

### How Events Flow Through the System

```mermaid
sequenceDiagram
    actor C as Customer
    participant LV as LiveView
    participant ET as Event Tracker
    participant PG as PostgreSQL
    participant OBAN as Oban Worker
    participant DASH as Admin Dashboard

    C->>LV: Visit page / Click CTA / Book wash
    LV->>ET: track_event("booking.started", %{service: "basic", source: "google"})
    ET->>PG: INSERT INTO events (non-blocking, async)

    Note over OBAN: Every hour
    OBAN->>PG: Aggregate events into materialized views
    PG-->>OBAN: Funnel metrics, cohort data

    Note over DASH: Real-time via LiveView
    DASH->>PG: Query aggregated metrics
    PG-->>DASH: Conversion rates, trends, experiment results
    DASH-->>C: Owner sees dashboard with actionable data
```

### Experiment Framework — Built-In A/B Testing

Every feature can run as an experiment:

```elixir
# In any LiveView — assign a variant
def mount(_params, session, socket) do
  variant = Experiments.assign(session_id, "pricing_page_layout")
  # variant is :control or :treatment_a

  {:ok, assign(socket, variant: variant)}
end

# In template — render based on variant
# <%= if @variant == :treatment_a do %>
#   <PricingGridWithSocialProof />
# <% else %>
#   <PricingGridControl />
# <% end %>

# Track conversion tied to variant
def handle_event("book_wash", params, socket) do
  Events.track(socket, "booking.completed", %{variant: socket.assigns.variant})
end
```

### The Owner Dashboard — Your Daily Decision Tool

```mermaid
graph TB
    subgraph "Top Row — Health at a Glance"
        KPI1[Weekly Revenue<br/>$X ↑↓ vs last week]
        KPI2[Active Subscribers<br/>N ↑↓ trend]
        KPI3[Bookings This Week<br/>N ↑↓ trend]
        KPI4[Conversion Rate<br/>Visit→Book %]
    end

    subgraph "Middle — Funnel This Week"
        F1[Visitors] --> F2[Signups]
        F2 --> F3[Bookings]
        F3 --> F4[Payments]
        F4 --> F5[Repeat/Subscribe]
    end

    subgraph "Bottom — Decisions Needed"
        EXP[Active Experiments<br/>with confidence levels]
        ALERTS[Alerts<br/>churn spike, drop in bookings, etc.]
        COHORT[Cohort View<br/>week-over-week retention curves]
    end
```

### What Gets Tracked from Day One (MVP)

| Event | Properties | Why |
|-------|-----------|-----|
| `page.viewed` | path, referrer, utm_source, utm_medium, device | Know where customers come from |
| `signup.completed` | method (email/google), referral_code | Track acquisition channel effectiveness |
| `booking.started` | service_type, is_subscriber | Measure intent |
| `booking.abandoned` | step (vehicle, address, time, payment), reason | Find friction points |
| `booking.completed` | service_type, price, discount, time_to_complete | Measure activation |
| `payment.succeeded` | amount, type (one_time/subscription), plan_id | Revenue tracking |
| `payment.failed` | error_reason, retry_count | Fix payment friction |
| `subscription.started` | plan_id, previous_one_time_count | Track upgrade path |
| `subscription.cancelled` | plan_id, reason, months_active, total_spent | Understand churn |
| `subscription.usage` | washes_used, washes_remaining, days_remaining | Predict churn risk |
| `review.submitted` | rating, nps_score, appointment_id | Service quality signal |
| `referral.sent` | channel (email/sms/link) | Viral growth tracking |
| `referral.converted` | referrer_id, plan_selected | Referral program ROI |

---

## Updated Tech Stack (additions)

| Layer | Technology | Why |
|-------|-----------|-----|
| Rate Limiting | Hammer | Configurable per-route rate limiting |
| Encryption | Cloak + Cloak.Ecto | Encrypt PII at rest (email, phone, address) |
| Security Scanning | Sobelow + MixAudit | Static analysis + dependency vulnerability checks |
| Event Tracking | Custom Ash resource + PostgreSQL | First-party analytics — no third-party data leakage |
| Materialized Views | PostgreSQL | Pre-aggregated funnel metrics for fast dashboard queries |
| Admin Dashboard | Phoenix LiveView | Real-time metrics dashboard, same stack |

---

## Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| API-first | JSON API alongside LiveView | Native apps later without rewriting business logic |
| Ash Domains | Separate contexts (Accounts, Scheduling, Billing, Operations) | Clean boundaries, testable, franchise-ready |
| Stripe | Over Square | Superior subscription management, webhooks, Elixir library maturity |
| Oban | For background jobs | Persistent, PostgreSQL-backed, perfect for reminders & billing cycles |
| Multi-tenant ready | Technician/Van models from day one | Schema supports multiple operators even though MVP is single |
| Subscription usage tracking | Separate table per billing period | Clean audit trail, prevents over-usage, easy reporting |

---

## What's Next

Ready to start **Phase 1 — Foundation**:
1. Initialize the Phoenix/Ash project
2. Set up the database schema
3. Write our first BDD test (customer signup)
4. Build from there iteratively

Shall we begin?
