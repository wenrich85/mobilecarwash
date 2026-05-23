# iOS Tech Backend Blockers

The iOS technician experience ships earnings and completed-history screens as stubs until these backend endpoints exist:

- `GET /api/v1/tech/earnings?period=week|month|year`
- `GET /api/v1/tech/appointments/history?limit=50`
- Optional: `GET /api/v1/tech/appointments/:id` for single-appointment polling/deep-link fetches without listing the next 24 hours.

Checklist and photo endpoints are implemented in this branch so the active wash flow can become live end to end.
