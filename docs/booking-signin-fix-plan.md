# Fix Plan — Booking Sign-In Dead-End

## The problem

A returning, already-registered customer cannot sign in from inside the booking
wizard, and is actively blocked from finishing as a guest:

- The in-flow sign-in control is a disabled stub —
  `"Sign in (coming soon)"` (`lib/mobile_car_wash_web/live/booking_live.ex:329-330`),
  with the comment *"No /sign-in LiveView route exists"* (`:320`).
- If they enter their email in guest checkout, the registered-account branch
  rejects them with **"An account with this email already exists. Please sign in
  instead."** (`:765-767`) — and there is nowhere in the flow to do so.

Net effect: their only path is to abandon the wizard, sign in at `/sign-in`
separately, and **start booking over**. This hits repeat customers (the best
ones) and locks them out of their saved vehicles/addresses.

## Why it was stubbed (the real constraint)

Sign-in establishes the session **cookie**, and only a controller can do that —
`AuthController.success/4` calls `store_in_session/2`
(`lib/mobile_car_wash_web/controllers/auth_controller.ex:5-27`). A LiveView
(`BookingLive`) **cannot set the session cookie**, so an inline username/password
form inside the wizard can't truly authenticate. That's the wall the stub avoided.

## Why a redirect round-trip is actually seamless here

The infrastructure to resume booking after leaving already exists:

- **Booking state is persisted** by `persist_booking_state/1`, keyed on a stable
  `session_id` (the `EnsureSessionId` plug cookie), via `Booking.SessionCache`
  (`lib/mobile_car_wash/booking/session_cache.ex`, 2h TTL).
- **On mount**, `BookingLive` restores both the step *and* the selections from
  `SessionCache`, then runs `StateMachine.resolve_step(restored_step, ctx)`
  (`booking_live.ex:~30-48`).
- Once `current_customer` is set, `resolve_step`/`maybe_skip` **auto-skip
  `:auth`** (`booking/state_machine.ex:71-73, 110`).

So: redirect to `/sign-in` → user authenticates → return to `/book` →
`on_mount :maybe_load_customer` populates `current_customer` →
`SessionCache` rehydrates their selections → `resolve_step` drops them **past auth,
right where they left off**. No lost work.

The only missing piece is **return-path handling** — `AuthController.success/4`
currently hardcodes the post-login redirect by role (`:customer -> ~p"/"`).

---

## Recommended fix (redirect round-trip + return path)

### Phase 1 — Carry a return path through sign-in

1. **New controller action** to stash the return path before sign-in.
   In `AuthController` (or a small `BookingAuthController`):
   ```elixir
   # GET /book/sign-in
   def booking_sign_in(conn, _params) do
     conn
     |> put_session(:return_to, "/book")
     |> redirect(to: ~p"/sign-in")
   end
   ```
   Route it under the `:browser` pipeline.

2. **Honor `:return_to` in `success/4`** for customers, with a local-path guard:
   ```elixir
   def success(conn, _activity, user, _token) do
     # ... existing store_token / store_in_session ...
     redirect_path = post_sign_in_path(conn, user)
     conn |> store_in_session(user) |> assign(:current_user, user)
     |> redirect(to: redirect_path)
   end

   defp post_sign_in_path(conn, %{role: :customer}) do
     case get_session(conn, :return_to) do
       "/" <> _ = path -> path   # local paths only — never trust an absolute URL
       _ -> ~p"/"
     end
   end
   defp post_sign_in_path(_conn, %{role: :admin}), do: ~p"/admin"
   defp post_sign_in_path(_conn, %{role: :technician}), do: ~p"/tech"
   defp post_sign_in_path(_conn, _), do: ~p"/"
   ```
   Delete `:return_to` from the session after use (`delete_session/2`).

### Phase 2 — Replace the disabled stub in the `:auth` step

In `booking_live.ex` (`:320-331`), swap the disabled button for a real link:
```heex
<.link navigate={~p"/book/sign-in"} class="btn btn-ghost btn-sm">
  Sign in to use saved vehicles &amp; addresses
</.link>
```
`navigate` does a full nav to the controller action, which is what we want (it
needs the controller round-trip to set the cookie). Booking state is already
persisted, so nothing is lost.

### Phase 3 — Turn the guest-collision error into a recovery, not a wall

In the `guest_checkout` handler, the registered-account branch
(`booking_live.ex:765-767`) returns a flat error string. Instead, flag it so the
template can offer the sign-in CTA inline:
```elixir
[_registered_customer] ->
  {:error, :needs_sign_in}
# ...
{:error, :needs_sign_in} ->
  {:noreply, assign(socket, guest_error: :needs_sign_in)}
```
Then in the template, when `@guest_error == :needs_sign_in`, render:
> "That email already has an account. **[Sign in to continue →](/book/sign-in)**"
instead of a dead-end message.

---

## Alternative considered (not recommended)

**In-LiveView credential check** — validate `:sign_in_with_password` inside
`BookingLive` to load the customer in memory and proceed guest-style, then mint
the real session at the Stripe-return controller. Rejected: the user is "logged
in" for booking but has **no real session** (header, `/appointments`, etc. still
show logged-out), credentials are handled outside the audited auth path, and it
duplicates rate-limiting/lockout logic. The redirect round-trip is simpler and
correct.

---

## Tests to add

1. **State machine** (pure, fast): registered `current_customer` present →
   `resolve_step(:auth, ctx)` returns `:vehicle` (already covered by skip logic —
   assert it explicitly).
2. **Controller**: `success/4` with `:return_to => "/book"` in session redirects a
   `:customer` to `/book`; ignores/strips a non-local `return_to`
   (`"//evil.com"`, `"https://evil.com"`).
3. **Feature/integration**: start booking as guest → enter a registered email →
   see the inline sign-in CTA → sign in → land back on `/book` at `:vehicle`
   (or later) with saved vehicles/addresses available and prior selections intact.

## Effort

Small. Three files: `auth_controller.ex` (return-path), `router.ex` (one route),
`booking_live.ex` (link + error branch). No schema or migration changes; reuses
existing `SessionCache` and `resolve_step`.

## Out of scope (separate friction items)

- Showing the running total before `:review` (price-reveal friction).
- Reordering `:photos` / making "skip" prominent.
- Surfacing slot availability before vehicle/address creation.
