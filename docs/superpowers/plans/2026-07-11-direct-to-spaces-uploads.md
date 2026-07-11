# Direct-to-Spaces Uploads + Tile-Based Concurrent Capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tech checklist photos are captured per-tile (tap tile → camera → back on grid), upload concurrently with progress/success/failure shown on each tile, and — in production — upload straight from the phone to DigitalOcean Spaces via presigned PUT URLs.

**Architecture:** One LiveView upload config per tile (`:before_front` … `:after_wheels`, 12 total) — the config name encodes photo_type + car_part, so concurrency needs no bookkeeping. Auto-upload + a shared progress callback auto-saves each photo on completion. Transport is switchable: `photo_storage == :s3` adds an `external:` presign callback (browser PUTs to Spaces); `:local` (dev/test) keeps today's channel path byte-for-byte.

**Tech Stack:** Elixir/Phoenix LiveView 1.1, Ash, ExAws.S3 (presigned PUT with signed headers), Oban, esbuild.

**Spec:** `docs/superpowers/specs/2026-07-11-direct-to-spaces-uploads-design.md`

## Global Constraints

- Work in worktree `/Users/wrich/Documents/MobileCarWash-worktrees/direct-to-spaces-uploads`, branch `feature/direct-to-spaces-uploads`. All commands run from that directory.
- TDD: every task writes its failing test first and shows the failure before implementing.
- `mix format` before every commit (`mix precommit` runs format+compile+test; the final task runs it in full).
- Photo accept list everywhere: `~w(.jpg .jpeg .png .webp)`; `max_file_size: 10_000_000`.
- Presigned PUT expiry: 300 seconds. Object keys: `appointments/<appointment_id>/<photo_type>_<uuid><ext>`.
- No flash messages for photo save results — all photo feedback renders on the tile/entry itself.
- Commit messages end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Verified harness facts (do not re-derive): `render_upload/3` percent is **incremental**; an oversized file makes `render_upload` return `{:error, [[ref, :too_large]]}` (it does not raise); `Phoenix.LiveViewTest.preflight_upload/1` exists and returns `{:ok, resp}` with the external callback's meta under `resp.entries`.

---

### Task 1: Replace the overlay with per-tile camera inputs (render layer)

The tech checklist currently captures photos through a full-screen overlay
(`show_photo_upload` assign, `show_upload`/`cancel_upload`/`save_photo`
events, single `:photo` upload config). This task deletes all of that and
renders one hidden camera-direct file input per area tile. Saving is wired
in Task 2 — this task's progress callback is a stub.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex`
- Test: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes: existing `@key_areas` / `@key_area_ids` module attrs, `area_photo/2`, `reload_photos/1`.
- Produces (later tasks rely on these exact names):
  - upload configs named `:"#{type}_#{area}"` for `type in [:before, :after]`, `area in @key_area_ids`
  - `defp handle_tile_progress(name, entry, socket)` (stub here, real in Task 2)
  - `defp tile_upload_name(type, area_id) :: atom`
  - `defp tile_upload_opts() :: keyword` (Task 8 adds `external:` to it)
  - `defp photo_tile(assigns)` function component; tile wrapper ids `#tile-before-front` etc.; forms `#before-photo-form`, `#after-photo-form`
  - assign `@tile_errors :: %{atom => String.t()}`

- [ ] **Step 1: Replace the stale overlay tests with failing tile-render tests**

In `test/mobile_car_wash_web/live/checklist_live_test.exs`:

1. Delete the entire `describe "photo upload overlay"` block (it tests the
   overlay this task removes).
2. In `describe "active wash regions"`, the in-progress test asserts
   `assert has_element?(view, "#before-photo-progress [phx-click='show_upload']")`
   — replace that line with:

```elixir
      assert has_element?(view, "#before-photo-form input[type='file']")
```

   The completed-checklist test asserts
   `refute has_element?(view, "#before-photo-progress [phx-click='show_upload']")`
   — replace that line with:

```elixir
      refute has_element?(view, "#before-photo-form input[type='file']")
```

3. Delete the module-level `open_overlay/1` helper (nothing opens an
   overlay anymore) and change `jpeg_entry/0` to take a name:

```elixir
  defp jpeg_entry(name) do
    %{
      name: name,
      content: <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 60_000),
      type: "image/jpeg"
    }
  end
```

4. Add a new describe block (reuses the same setup shape the overlay block had):

```elixir
  describe "tile-based photo capture" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      {:ok,
       conn: sign_in(conn, user),
       tech: tech,
       customer: customer,
       appointment: appointment,
       checklist: checklist}
    end

    test "every key area tile exposes its own camera-direct input", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      for area <- ~w(front rear driver_side passenger_side interior wheels) do
        assert has_element?(
                 view,
                 "#before-photo-form input[type='file'][name='before_#{area}']"
               )
      end

      # Tapping a tile opens the rear camera directly.
      assert html =~ ~s(capture="environment")

      # Downscale hook wraps the grid (the input itself is claimed by
      # LiveView's internal LiveFileUpload hook).
      assert has_element?(view, "#before-photo-form[phx-hook='ImageDownscale']")

      # The overlay and its Save button are gone.
      refute has_element?(view, "#checklist-photo-form")
      refute html =~ "Save Photo"
    end

    test "completed checklists hide all capture inputs", %{
      conn: conn,
      tech: tech,
      customer: customer
    } do
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :completed)

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      # Completed checklist: capture affordances hidden on both grids.
      refute has_element?(view, "#after-photo-form input[type='file']")
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: FAIL — `#before-photo-form` selectors match nothing (form doesn't exist yet); the two edited stable-region assertions fail the same way.

- [ ] **Step 3: Implement the tile render layer in `checklist_live.ex`**

3a. Below `@key_area_ids`, add:

```elixir
  # One upload config per tile. The config NAME encodes photo_type and
  # car_part (e.g. :before_front), so concurrent uploads need no
  # entry-to-area bookkeeping.
  @tile_uploads for type <- [:before, :after], area <- @key_area_ids, do: :"#{type}_#{area}"
```

3b. In the success `mount` clause, replace the existing
`|> allow_upload(:photo, ...)` pipe (the whole block ending `auto_upload: true )`) with:

```elixir
          |> assign(tile_errors: %{})
          |> then(fn sock ->
            Enum.reduce(@tile_uploads, sock, fn name, s ->
              allow_upload(s, name, tile_upload_opts())
            end)
          end)
```

Also delete `show_photo_upload: nil,` from all three mount `assign` lists.

3c. Add near the photo helpers:

```elixir
  defp tile_upload_opts do
    [
      accept: ~w(.jpg .jpeg .png .webp),
      max_entries: 1,
      max_file_size: 10_000_000,
      auto_upload: true,
      progress: &handle_tile_progress/3
    ]
  end

  # Real implementation lands with auto-save (next task).
  defp handle_tile_progress(_name, _entry, socket), do: {:noreply, socket}

  defp tile_upload_name(type, area_id), do: :"#{type}_#{area_id}"

  defp parse_tile_name(name) do
    [type, area] = name |> Atom.to_string() |> String.split("_", parts: 2)
    {String.to_existing_atom(type), String.to_existing_atom(area)}
  end
```

(`parse_tile_name/1` is unused until Task 2 — that's fine, it compiles;
if the compiler warns about it being unused, add it in Task 2 instead.)

3d. Delete these event handlers and helpers entirely:
`handle_event("show_upload", ...)`, `handle_event("cancel_upload", ...)`,
`handle_event("save_photo", ...)`, `defp save_completed_photo/1`,
`defp save_error_message/1`, `defp area_label/1`, `defp area_instruction/1`.
Keep `handle_event("validate_upload", ...)` (the tile forms use it) and
`defp upload_error_to_string/1` (tiles reuse it; Task 4 relocates it).

3e. Replace the **before-grid** markup. Currently:

```heex
            <div class="grid grid-cols-2 gap-3">
              <div :for={area <- @key_areas}>
                <% photo = area_photo(@before_photos, area.id) %>
                ... saved tile / empty button / completed empty div ...
              </div>
            </div>
```

becomes:

```heex
            <form
              id="before-photo-form"
              phx-change="validate_upload"
              phx-hook="ImageDownscale"
              class="grid grid-cols-2 gap-3"
            >
              <.photo_tile
                :for={area <- @key_areas}
                area={area}
                type={:before}
                photo={area_photo(@before_photos, area.id)}
                ghost={nil}
                upload={@uploads[tile_upload_name(:before, area.id)]}
                tile_error={@tile_errors[tile_upload_name(:before, area.id)]}
                completed={@checklist.status == :completed}
              />
            </form>
```

3f. Replace the **after-grid** markup (the `div` with
`:if={all_required_complete?(@items) or @checklist.status == :completed}`
containing the same per-area tiles) with:

```heex
            <form
              :if={all_required_complete?(@items) or @checklist.status == :completed}
              id="after-photo-form"
              phx-change="validate_upload"
              phx-hook="ImageDownscale"
              class="grid grid-cols-2 gap-3"
            >
              <.photo_tile
                :for={area <- @key_areas}
                area={area}
                type={:after}
                photo={area_photo(@after_photos, area.id)}
                ghost={area_photo(@before_photos, area.id)}
                upload={@uploads[tile_upload_name(:after, area.id)]}
                tile_error={@tile_errors[tile_upload_name(:after, area.id)]}
                completed={@checklist.status == :completed}
              />
            </form>
```

3g. Delete the entire "Photo Upload Overlay" block
(`<div :if={@show_photo_upload} class="fixed inset-0 z-50 ...">` through its
closing `</div>`).

3h. Add the tile component after `render/1`:

```elixir
  # One grid tile. States, in precedence order: uploading (entry, no
  # errors) → upload failed (entry with errors) → saved (persisted photo)
  # → capture label (empty) → completed-and-missing placeholder.
  defp photo_tile(assigns) do
    entry = List.first(assigns.upload.entries)

    errors =
      if entry,
        do: upload_errors(assigns.upload, entry) ++ upload_errors(assigns.upload),
        else: upload_errors(assigns.upload)

    assigns = assign(assigns, entry: entry, upload_errs: errors)

    ~H"""
    <div id={"tile-#{@type}-#{@area.id}"}>
      <div
        :if={@entry && @upload_errs == []}
        class="relative h-40 overflow-hidden rounded-2xl shadow"
      >
        <.live_img_preview entry={@entry} class="h-full w-full object-cover" />
        <div class="absolute inset-x-2 bottom-2">
          <progress
            class="progress progress-primary h-1.5 w-full"
            value={@entry.progress}
            max="100"
          >
          </progress>
        </div>
        <p class="absolute left-2 top-2 rounded-full bg-black/40 px-2 py-0.5 text-xs text-white">
          {@area.label}
        </p>
      </div>

      <div
        :if={@entry && @upload_errs != []}
        class="flex h-40 w-full flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-error bg-error/5 px-3 text-center"
      >
        <p class="text-sm font-bold text-error">{@area.label}</p>
        <p class="text-xs text-error">{upload_error_to_string(hd(@upload_errs))}</p>
        <button
          type="button"
          class="btn btn-outline btn-error btn-xs"
          phx-click="retry_tile_upload"
          phx-value-name={@upload.name}
          phx-value-ref={@entry.ref}
        >
          Try again
        </button>
      </div>

      <div :if={!@entry && @photo} class="relative h-40 overflow-hidden rounded-2xl shadow">
        <img src={@photo.file_path} class="h-full w-full object-cover" />
        <div
          :if={@ghost}
          class="absolute bottom-2 left-2 h-12 w-12 overflow-hidden rounded-lg border-2 border-white shadow"
        >
          <img src={@ghost.file_path} class="h-full w-full object-cover" />
        </div>
        <div class={[
          "absolute inset-0 flex flex-col justify-end bg-gradient-to-t from-black/60 to-transparent p-2",
          @ghost && "pl-16"
        ]}>
          <p class="text-xs font-bold leading-tight text-white">{@area.label}</p>
        </div>
        <div class="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full bg-success shadow">
          <span class="text-xs font-bold text-white">✓</span>
        </div>
        <label
          :if={!@completed}
          for={@upload.ref}
          class="absolute left-2 top-2 cursor-pointer rounded-full bg-black/40 px-2 py-0.5 text-xs text-white"
        >
          Retake
        </label>
      </div>

      <label
        :if={!@entry && !@photo && !@completed}
        for={@upload.ref}
        class={[
          "relative flex h-40 w-full cursor-pointer flex-col items-center justify-center gap-1",
          "overflow-hidden rounded-2xl border-2 border-dashed transition-colors",
          tile_accent(@type)
        ]}
      >
        <img
          :if={@ghost}
          src={@ghost.file_path}
          class="absolute inset-0 h-full w-full object-cover opacity-20"
        />
        <span class="relative text-5xl font-thin opacity-70">+</span>
        <span class="relative text-sm font-bold">{@area.label}</span>
        <span class="relative px-3 text-center text-xs leading-tight text-base-content/70">
          {@area.instruction}
        </span>
        <p :if={@tile_error} class="relative text-xs font-semibold text-error">{@tile_error}</p>
      </label>

      <div
        :if={!@entry && !@photo && @completed}
        class="flex h-40 items-center justify-center rounded-2xl border border-base-300 bg-base-200/40 px-3 text-center text-xs text-base-content/60"
      >
        No {@type} photo captured for {@area.label}.
      </div>

      <.live_file_input
        :if={!@completed}
        upload={@upload}
        capture="environment"
        class="sr-only"
      />
    </div>
    """
  end

  defp tile_accent(:before), do: "border-warning bg-warning/5 text-warning active:bg-warning/20"
  defp tile_accent(:after), do: "border-success bg-success/5 text-success active:bg-success/20"
```

3i. Add the retry event handler next to `handle_event("validate_upload", ...)`
(the error-tile test lands in Task 3, but the button renders now and must
not crash):

```elixir
  def handle_event("retry_tile_upload", %{"name" => name, "ref" => ref}, socket) do
    name = String.to_existing_atom(name)

    {:noreply,
     socket
     |> cancel_upload(name, ref)
     |> update(:tile_errors, &Map.delete(&1, name))}
  end
```

- [ ] **Step 4: Run the checklist tests to verify they pass**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: PASS (all tests, including the two edited stable-region tests).

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "feat(checklist): per-tile camera inputs replace the photo overlay

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Auto-save tile uploads with per-tile progress

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex` (replace the `handle_tile_progress/3` stub)
- Test: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes: `parse_tile_name/1`, `reload_photos/1`, `maybe_complete_wash/1`, `AppointmentTracker.broadcast_photo/2`, `PhotoUpload.save_file/5` — all exist.
- Produces: `defp save_tile_file(meta, appointment_id, client_name, photo_type, area)` with a `%{path: path}` clause (Task 8 adds a `%{key: key}` clause); `defp save_error_message(reason)` taking a scalar reason.

- [ ] **Step 1: Write the failing tests** (inside `describe "tile-based photo capture"`)

```elixir
    test "a completed tile upload auto-saves with its area and type", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      front = file_input(view, "#before-photo-form", :before_front, [jpeg_entry("front.jpg")])

      render_upload(front, "front.jpg", 50)
      # Mid-transfer: progress bar lives in the tile the photo belongs to.
      assert has_element?(view, "#tile-before-front progress")

      # percent is incremental — the second half completes the transfer
      # and the progress callback consumes + saves automatically.
      render_upload(front, "front.jpg", 50)

      html = render(view)
      refute html =~ "Photo saved."

      require Ash.Query

      saved =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
        |> Ash.read!()

      assert [%{car_part: :front, uploaded_by: :technician}] = saved

      # Tile now renders the persisted photo.
      assert has_element?(view, "#tile-before-front img")
      refute has_element?(view, "#tile-before-front progress")
    end

    test "two tiles upload concurrently, each with its own progress", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      front = file_input(view, "#before-photo-form", :before_front, [jpeg_entry("front.jpg")])
      rear = file_input(view, "#before-photo-form", :before_rear, [jpeg_entry("rear.jpg")])

      render_upload(front, "front.jpg", 50)
      render_upload(rear, "rear.jpg", 50)

      assert has_element?(view, "#tile-before-front progress")
      assert has_element?(view, "#tile-before-rear progress")

      render_upload(front, "front.jpg", 50)
      render_upload(rear, "rear.jpg", 50)

      require Ash.Query

      saved =
        MobileCarWash.Operations.Photo
        |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
        |> Ash.read!()

      assert Enum.sort(Enum.map(saved, & &1.car_part)) == [:front, :rear]
    end
```

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: FAIL — the stub never consumes, so no Photo rows exist (`assert [%{...}] = []` fails) and `#tile-before-front img` is absent.

- [ ] **Step 3: Implement the real progress callback**

Replace the stub with:

```elixir
  # Auto-save: each tile's entry is consumed the moment its transfer
  # completes. Success re-renders the tile with the persisted photo;
  # failure lands in @tile_errors for that tile (no flash either way).
  defp handle_tile_progress(name, entry, socket) do
    if entry.done? do
      {photo_type, area} = parse_tile_name(name)
      appointment_id = socket.assigns.appointment.id

      result =
        consume_uploaded_entry(socket, entry, fn meta ->
          {:ok, save_tile_file(meta, appointment_id, entry.client_name, photo_type, area)}
        end)

      case result do
        {:ok, _photo} ->
          AppointmentTracker.broadcast_photo(appointment_id, photo_type)

          {:noreply,
           socket
           |> update(:tile_errors, &Map.delete(&1, name))
           |> reload_photos()
           |> maybe_complete_wash()}

        {:error, reason} ->
          {:noreply, update(socket, :tile_errors, &Map.put(&1, name, save_error_message(reason)))}
      end
    else
      {:noreply, update(socket, :tile_errors, &Map.delete(&1, name))}
    end
  end

  defp save_tile_file(%{path: path}, appointment_id, client_name, photo_type, area) do
    PhotoUpload.save_file(appointment_id, path, client_name, photo_type,
      uploaded_by: :technician,
      car_part: area
    )
  end

  defp save_error_message(reason) when is_binary(reason), do: "Could not save photo: #{reason}"
  defp save_error_message(_reason), do: "Could not save photo — please try again."
```

- [ ] **Step 4: Run the checklist tests to verify everything passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "feat(checklist): concurrent tile uploads auto-save on completion

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: On-tile error reporting and retry

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex` (only if tests reveal gaps — the render/retry paths were built in Tasks 1–2)
- Test: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes: `upload_error_to_string/1` messages ("That photo is too large (max 10 MB)." etc.), `retry_tile_upload` event, `@tile_errors`.
- Produces: verified on-tile error behavior later tasks must not regress.

- [ ] **Step 1: Write the failing tests** (inside `describe "tile-based photo capture"`)

```elixir
    test "an oversized upload reports on its tile with a retry control", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      big = %{
        name: "huge.jpg",
        content: :binary.copy(<<0xFF>>, 10_000_001),
        type: "image/jpeg"
      }

      input = file_input(view, "#before-photo-form", :before_front, [big])
      assert {:error, [[_ref, :too_large]]} = render_upload(input, "huge.jpg")

      assert render(view) =~ "That photo is too large"
      assert has_element?(view, "#tile-before-front button", "Try again")

      # Try again clears the dead entry and returns the tile to capture state.
      view |> element("#tile-before-front button", "Try again") |> render_click()

      refute render(view) =~ "That photo is too large"
      assert has_element?(view, "#tile-before-front label[for]")
    end

    test "a failed save reports on the tile, not via flash", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      # A file under 4 bytes trips PhotoUpload's "File too small to
      # validate" — a deterministic, non-destructive save failure.
      tiny = %{name: "tiny.jpg", content: <<0xFF, 0xD8>>, type: "image/jpeg"}

      input = file_input(view, "#before-photo-form", :before_rear, [tiny])
      render_upload(input, "tiny.jpg")

      html = render(view)
      assert html =~ "Could not save photo"
      refute html =~ "Photo saved."

      require Ash.Query

      assert [] =
               MobileCarWash.Operations.Photo
               |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
               |> Ash.read!()

      # Tile is immediately retakeable (entry was consumed).
      assert has_element?(view, "#tile-before-rear label[for]")
    end
```

- [ ] **Step 2: Run to verify current behavior**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: the too-large test may already PASS (render path built in Task 1);
the failed-save test exercises the `{:error, reason}` branch of
`handle_tile_progress/3` and should PASS if Task 2 was implemented exactly
as written. If both pass immediately, treat this task as regression armor —
verify the assertions actually exercise the branches by temporarily breaking
`save_error_message/1` (change the message, watch the test fail, restore).
If either fails, fix the render/handler code — the intended behavior is
exactly what the tests state.

- [ ] **Step 3: Run the full file once more**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: PASS, 0 failures.

- [ ] **Step 4: Format and commit**

```bash
mix format
git add test/mobile_car_wash_web/live/checklist_live_test.exs lib/mobile_car_wash_web/live/checklist_live.ex
git commit -m "test(checklist): on-tile upload and save error reporting

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Customer uploader — per-entry error display

Failures must report on the picture itself in the customer modal too.
The shared error copy moves into `PhotoUploader` so both surfaces use one
source of truth.

**Files:**
- Modify: `lib/mobile_car_wash_web/components/photo_uploader.ex`
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex` (delete its private `upload_error_to_string/1`, call the shared one)
- Test: `test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`

**Interfaces:**
- Produces: `MobileCarWashWeb.PhotoUploader.error_message(reason :: atom) :: String.t()` — public, used by `ChecklistLive` and Task 8's `:external_client_failure` clause.
- Changes: `PhotoUploader.entry_preview` now requires an `upload` assign (the `%UploadConfig{}`); `uploader/1` passes it.

- [ ] **Step 1: Write the failing test** (in `appointments_photo_upload_test.exs`, inside `describe "Problem Area Photos modal"`)

```elixir
    test "an oversized photo reports its error on the preview card", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer.id)
      conn = sign_in(conn, customer)

      {:ok, view, _html} = live(conn, ~p"/appointments")

      view
      |> element("button[phx-value-id='#{appt.id}']", "Problem Area Photos")
      |> render_click()

      big = %{
        name: "huge.jpg",
        content: :binary.copy(<<0xFF>>, 10_000_001),
        type: "image/jpeg"
      }

      input = file_input(view, "#photo-upload-form-#{appt.id}", :problem_photo_library, [big])
      assert {:error, [[_ref, :too_large]]} = render_upload(input, "huge.jpg")

      assert render(view) =~ "That photo is too large"
    end
```

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`
Expected: FAIL — no error text renders (entry_preview shows only image + progress today).

- [ ] **Step 3: Implement**

3a. In `photo_uploader.ex`, add the public message function:

```elixir
  @doc "Human-readable message for a LiveView upload error atom."
  def error_message(:too_large), do: "That photo is too large (max 10 MB)."
  def error_message(:not_accepted), do: "Use a JPG, PNG, or WebP photo."
  def error_message(:too_many_files), do: "Too many photos at once."
  def error_message(:external_client_failure),
    do: "Upload failed — check your connection and try again."

  def error_message(_), do: "Upload failed — remove the photo and try again."
```

3b. Update `uploader/1` to pass the config into the previews — the two
`entry_preview` call lines become:

```heex
        <.entry_preview
          :for={entry <- @camera_upload.entries}
          entry={entry}
          upload={@camera_upload}
          source="camera"
        />
        <.entry_preview
          :for={entry <- @library_upload.entries}
          entry={entry}
          upload={@library_upload}
          source="library"
        />
```

3c. Replace `entry_preview/1` (attrs and body) with:

```elixir
  # In-flight preview with progress bar + cancel button; failed entries
  # show their error on the card itself. Source tag lets the parent know
  # which upload config to cancel against.
  attr :entry, :any, required: true
  attr :upload, :any, required: true
  attr :source, :string, required: true

  defp entry_preview(assigns) do
    assigns = assign(assigns, :errs, upload_errors(assigns.upload, assigns.entry))

    ~H"""
    <div class="relative">
      <.live_img_preview
        :if={@errs == []}
        entry={@entry}
        class="w-full aspect-square object-cover rounded-2xl shadow-sm"
      />
      <div
        :if={@errs != []}
        class="flex aspect-square w-full flex-col items-center justify-center gap-1 rounded-2xl border-2 border-dashed border-error bg-error/5 px-2 text-center"
      >
        <p class="text-xs font-semibold text-error">{error_message(hd(@errs))}</p>
        <p class="max-w-full truncate text-xs text-base-content/60">{@entry.client_name}</p>
      </div>
      <div :if={@errs == []} class="absolute inset-x-2 bottom-2">
        <progress class="progress progress-primary w-full h-1.5" value={@entry.progress} max="100" />
      </div>
      <button
        type="button"
        class="absolute top-2 right-2 btn btn-circle btn-xs bg-base-100 border border-base-300 text-base-content"
        phx-click="cancel_photo_upload"
        phx-value-ref={@entry.ref}
        phx-value-source={@source}
        aria-label={if @errs == [], do: "Cancel upload", else: "Remove failed photo"}
      >
        ✕
      </button>
    </div>
    """
  end
```

3d. In `checklist_live.ex`: delete `defp upload_error_to_string/1` and, in
`photo_tile`, change `upload_error_to_string(hd(@upload_errs))` to
`MobileCarWashWeb.PhotoUploader.error_message(hd(@upload_errs))`.

- [ ] **Step 4: Run both affected suites**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/appointments_photo_upload_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs test/mobile_car_wash_web/components/photo_uploader_test.exs`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/components/photo_uploader.ex lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/appointments_photo_upload_test.exs
git commit -m "feat(photos): per-entry error display in the customer uploader

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: PhotoUpload backend — `save_external_file/5` and friends

**Files:**
- Modify: `lib/mobile_car_wash/operations/photo_upload.ex`
- Test (create): `test/mobile_car_wash/operations/photo_upload_external_test.exs`

**Interfaces:**
- Produces (exact signatures Task 6/8 consume):
  - `PhotoUpload.external_uploads?() :: boolean` — `storage_backend() == :s3`
  - `PhotoUpload.object_key(appointment_id, photo_type, original_filename) :: String.t()` — `"appointments/<id>/<type>_<uuid><ext>"`
  - `PhotoUpload.save_external_file(appointment_id, key, original_filename, photo_type, opts) :: {:ok, Photo.t()} | {:error, term}` — same opts as `save_file/5` (`:uploaded_by`, `:caption`, `:checklist_item_id`, `:car_part`, `:idempotency_key`)
  - private `create_photo_record/5` shared by both save paths

- [ ] **Step 1: Write the failing tests**

Create `test/mobile_car_wash/operations/photo_upload_external_test.exs`:

```elixir
defmodule MobileCarWash.Operations.PhotoUploadExternalTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  require Ash.Query

  defp create_appointment do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ext-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Ext Customer",
        phone: "+15125550801"
      })
      |> Ash.create()

    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Ext Wash",
        slug: "ext-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1 Ext",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      MobileCarWash.Scheduling.Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    appt
  end

  describe "object_key/3" do
    test "builds the appointments/<id>/<type>_<uuid><ext> shape" do
      key = PhotoUpload.object_key("abc-123", :before, "IMG 1.JPG")

      assert key =~ ~r|^appointments/abc-123/before_[0-9a-f-]{36}\.jpg$|
    end
  end

  describe "save_external_file/5" do
    test "creates a Photo row whose file_path is the object key" do
      appt = create_appointment()
      key = PhotoUpload.object_key(appt.id, :before, "front.jpg")

      assert {:ok, photo} =
               PhotoUpload.save_external_file(appt.id, key, "front.jpg", :before,
                 uploaded_by: :technician,
                 car_part: :front
               )

      assert photo.file_path == key
      assert photo.photo_type == :before
      assert photo.car_part == :front
      assert photo.uploaded_by == :technician
      assert photo.content_type == "image/jpeg"
    end

    test "replaces an existing photo in the same slot" do
      appt = create_appointment()
      key1 = PhotoUpload.object_key(appt.id, :before, "a.jpg")
      key2 = PhotoUpload.object_key(appt.id, :before, "b.jpg")

      {:ok, _first} =
        PhotoUpload.save_external_file(appt.id, key1, "a.jpg", :before, car_part: :front)

      {:ok, second} =
        PhotoUpload.save_external_file(appt.id, key2, "b.jpg", :before, car_part: :front)

      live =
        Photo
        |> Ash.Query.filter(
          appointment_id == ^appt.id and photo_type == :before and car_part == :front and
            is_nil(deleted_at)
        )
        |> Ash.read!(authorize?: false)

      assert [%{id: id}] = live
      assert id == second.id
    end

    test "enqueues AI analysis for customer problem-area photos only" do
      appt = create_appointment()

      Oban.Testing.with_testing_mode(:manual, fn ->
        key = PhotoUpload.object_key(appt.id, :problem_area, "spot.jpg")

        {:ok, _photo} =
          PhotoUpload.save_external_file(appt.id, key, "spot.jpg", :problem_area,
            uploaded_by: :customer
          )

        assert_enqueued(worker: MobileCarWash.AI.PhotoAnalyzerWorker)

        key2 = PhotoUpload.object_key(appt.id, :before, "front.jpg")

        {:ok, tech_photo} =
          PhotoUpload.save_external_file(appt.id, key2, "front.jpg", :before,
            uploaded_by: :technician,
            car_part: :front
          )

        refute_enqueued(
          worker: MobileCarWash.AI.PhotoAnalyzerWorker,
          args: %{photo_id: tech_photo.id}
        )
      end)
    end

    test "returns the existing photo for a repeated idempotency key" do
      appt = create_appointment()
      key = PhotoUpload.object_key(appt.id, :before, "front.jpg")

      {:ok, first} =
        PhotoUpload.save_external_file(appt.id, key, "front.jpg", :before,
          car_part: :front,
          idempotency_key: "idem-1"
        )

      {:ok, second} =
        PhotoUpload.save_external_file(appt.id, key, "front.jpg", :before,
          car_part: :front,
          idempotency_key: "idem-1"
        )

      assert first.id == second.id
    end

    test "rejects extensions outside the allow-list" do
      appt = create_appointment()

      assert {:error, "Invalid image file"} =
               PhotoUpload.save_external_file(
                 appt.id,
                 "appointments/#{appt.id}/before_x.gif",
                 "x.gif",
                 :before,
                 car_part: :front
               )
    end
  end

  describe "external_uploads?/0" do
    test "true only when the backend is :s3" do
      previous = Application.get_env(:mobile_car_wash, :photo_storage, :local)
      on_exit(fn -> Application.put_env(:mobile_car_wash, :photo_storage, previous) end)

      Application.put_env(:mobile_car_wash, :photo_storage, :local)
      refute PhotoUpload.external_uploads?()

      Application.put_env(:mobile_car_wash, :photo_storage, :s3)
      assert PhotoUpload.external_uploads?()
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash/operations/photo_upload_external_test.exs`
Expected: FAIL — `PhotoUpload.object_key/3` is undefined (UndefinedFunctionError), likewise `save_external_file/5` and `external_uploads?/0`.

- [ ] **Step 3: Implement in `photo_upload.ex`**

3a. Public additions (place near `storage_backend/0`):

```elixir
  @allowed_extensions ~w(.jpg .jpeg .png .webp)

  @doc "True when uploads should go straight to object storage via presigned URLs."
  def external_uploads?, do: storage_backend() == :s3

  @doc """
  Builds the object key for a photo. Same shape the channel path stores,
  so display, cleanup, and AI analysis work identically for both paths.
  """
  def object_key(appointment_id, photo_type, original_filename) do
    ext = Path.extname(original_filename) |> String.downcase()
    "appointments/#{appointment_id}/#{photo_type}_#{Ash.UUID.generate()}#{ext}"
  end

  @doc """
  Records a photo whose bytes were uploaded directly to object storage by
  the client (presigned PUT). No byte validation is possible here — the
  server never sees the file — so only the extension allow-list applies.
  """
  def save_external_file(appointment_id, key, original_filename, photo_type, opts \\ []) do
    ext = Path.extname(original_filename) |> String.downcase()
    idempotency_key = Keyword.get(opts, :idempotency_key)
    car_part = Keyword.get(opts, :car_part)

    cond do
      ext not in @allowed_extensions ->
        {:error, "Invalid image file"}

      photo = get_idempotent_photo(idempotency_key) ->
        {:ok, photo}

      true ->
        :ok = soft_delete_existing_slot(appointment_id, photo_type, car_part)
        create_photo_record(appointment_id, key, original_filename, photo_type, opts)
    end
  end
```

Also change `validate_file_content/2`'s hardcoded
`ext in ~w(.jpg .jpeg .png .webp)` to `ext in @allowed_extensions` (module
attribute must be defined above its first use — put it near the top with
the other attributes).

3b. Extract the record-creation block. In `do_save_file_validated/6`, the
success branch currently builds `changeset_attrs`, creates the Photo, and
calls `maybe_enqueue_ai_analysis/1`. Replace that whole `{:ok, url_path} ->`
branch body with `create_photo_record(appointment_id, url_path, original_filename, photo_type, opts)`
and move the code into:

```elixir
  # Shared tail of both save paths: build the changeset, insert, enqueue AI.
  # `storage_path` is a PhotoController URL path (local) or an S3 object
  # key (both s3 flavors) — Photo.file_path stores it verbatim.
  defp create_photo_record(appointment_id, storage_path, original_filename, photo_type, opts) do
    uploaded_by = Keyword.get(opts, :uploaded_by, :technician)
    caption = Keyword.get(opts, :caption)
    checklist_item_id = Keyword.get(opts, :checklist_item_id)
    car_part = Keyword.get(opts, :car_part)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    changeset_attrs = %{
      file_path: storage_path,
      original_filename: original_filename,
      content_type: MIME.from_path(original_filename),
      photo_type: photo_type,
      caption: caption,
      uploaded_by: uploaded_by
    }

    changeset_attrs =
      if car_part, do: Map.put(changeset_attrs, :car_part, car_part), else: changeset_attrs

    changeset_attrs =
      if idempotency_key,
        do: Map.put(changeset_attrs, :idempotency_key, idempotency_key),
        else: changeset_attrs

    case Photo
         |> Ash.Changeset.for_create(:upload, changeset_attrs)
         |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
         |> then(fn cs ->
           if checklist_item_id do
             Ash.Changeset.force_change_attribute(cs, :checklist_item_id, checklist_item_id)
           else
             cs
           end
         end)
         |> Ash.create() do
      {:ok, photo} = ok ->
        maybe_enqueue_ai_analysis(photo)
        ok

      other ->
        other
    end
  end
```

`do_save_file_validated/6` keeps its upload dispatch and error clause; its
duplicated attrs-building code is deleted.

- [ ] **Step 4: Run the new tests plus the existing photo suites**

Run: `MIX_ENV=test mix test test/mobile_car_wash/operations/photo_upload_external_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`
Expected: PASS (extraction must not change channel-path behavior).

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash/operations/photo_upload.ex test/mobile_car_wash/operations/photo_upload_external_test.exs
git commit -m "feat(photos): save_external_file for direct-to-storage uploads

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Presigned PUT URLs

**Files:**
- Modify: `lib/mobile_car_wash/operations/photo_upload.ex`
- Test: `test/mobile_car_wash/operations/photo_upload_external_test.exs`

**Interfaces:**
- Produces:
  - `PhotoUpload.presign_put(key, content_type) :: {:ok, url} | {:error, term}` — 300s expiry, Content-Type signed
  - `PhotoUpload.external_entry_meta(entry, appointment_id, photo_type) :: {:ok, map} | {:error, term}` — meta is `%{uploader: "S3PUT", url: url, headers: %{"content-type" => ct}, key: key}` (Task 7's JS and Task 8's callbacks depend on these exact meta keys)

- [ ] **Step 1: Write the failing tests** (append to `photo_upload_external_test.exs`)

```elixir
  describe "presign_put/2 and external_entry_meta/3" do
    setup do
      prev_key = Application.get_env(:ex_aws, :access_key_id)
      prev_secret = Application.get_env(:ex_aws, :secret_access_key)
      Application.put_env(:ex_aws, :access_key_id, "test-access-key")
      Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

      on_exit(fn ->
        Application.put_env(:ex_aws, :access_key_id, prev_key)
        Application.put_env(:ex_aws, :secret_access_key, prev_secret)
      end)

      :ok
    end

    test "presign_put returns a 5-minute PUT URL with the content type signed" do
      {:ok, url} = PhotoUpload.presign_put("appointments/abc/before_x.jpg", "image/jpeg")

      assert url =~ "appointments/abc/before_x.jpg"
      assert url =~ "X-Amz-Expires=300"
      assert url =~ "X-Amz-Signature="
      # Content-Type participates in the signature (URL-encoded ';' = %3B).
      assert url =~ "content-type%3Bhost"
    end

    test "external_entry_meta builds the uploader payload" do
      entry = %Phoenix.LiveView.UploadEntry{client_name: "front.jpg", client_type: "image/jpeg"}

      {:ok, meta} = PhotoUpload.external_entry_meta(entry, "appt-1", :before)

      assert meta.uploader == "S3PUT"
      assert meta.headers == %{"content-type" => "image/jpeg"}
      assert meta.key =~ ~r|^appointments/appt-1/before_[0-9a-f-]{36}\.jpg$|
      assert meta.url =~ meta.key
    end
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash/operations/photo_upload_external_test.exs`
Expected: FAIL — `presign_put/2` undefined.

- [ ] **Step 3: Implement (place next to `presign_url/1` in `photo_upload.ex`)**

```elixir
  @presign_put_expiry 300

  @doc """
  Presigns a PUT of `key` so the client can upload straight to the bucket.
  Content-Type is signed, so the client must send exactly this type.
  Works on AWS S3 and DigitalOcean Spaces (via the configured endpoint).
  """
  def presign_put(key, content_type) do
    region = Application.get_env(:mobile_car_wash, :s3_region, "us-east-1")
    config = ExAws.Config.new(:s3, region: region)

    ExAws.S3.presigned_url(config, :put, s3_bucket(), key,
      expires_in: @presign_put_expiry,
      headers: [{"Content-Type", content_type}]
    )
  end

  @doc """
  Builds the meta map LiveView hands to the JS uploader for an external
  entry. `key` rides along so consume-time code knows where the bytes are.
  """
  def external_entry_meta(entry, appointment_id, photo_type) do
    key = object_key(appointment_id, photo_type, entry.client_name)

    case presign_put(key, entry.client_type) do
      {:ok, url} ->
        {:ok,
         %{
           uploader: "S3PUT",
           url: url,
           headers: %{"content-type" => entry.client_type},
           key: key
         }}

      {:error, _} = error ->
        error
    end
  end
```

- [ ] **Step 4: Run to verify PASS**

Run: `MIX_ENV=test mix test test/mobile_car_wash/operations/photo_upload_external_test.exs`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash/operations/photo_upload.ex test/mobile_car_wash/operations/photo_upload_external_test.exs
git commit -m "feat(photos): presigned PUT URLs for direct-to-storage uploads

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: S3PUT JS uploader

No JS test runner exists in this project — verification is a successful
esbuild compile plus the staging checklist in the spec.

**Files:**
- Create: `assets/js/uploaders/s3_put.js`
- Modify: `assets/js/app.js`

**Interfaces:**
- Consumes: `entry.meta.url`, `entry.meta.headers` (exact keys from Task 6's `external_entry_meta/3`).
- Produces: uploader registered under the name `"S3PUT"` (must match the `uploader:` value in the meta).

- [ ] **Step 1: Create `assets/js/uploaders/s3_put.js`**

```javascript
// LiveView external uploader: PUTs the file straight to object storage
// (DigitalOcean Spaces / S3) using the presigned URL the server put in
// entry.meta. Progress feeds LiveView's normal entry progress, so tile
// and modal progress bars work unchanged.
export const S3PUT = function (entries, onViewError) {
  entries.forEach(entry => {
    const xhr = new XMLHttpRequest()
    onViewError(() => xhr.abort())

    xhr.onload = () =>
      xhr.status >= 200 && xhr.status < 300 ? entry.progress(100) : entry.error()
    xhr.onerror = () => entry.error()

    xhr.upload.addEventListener("progress", event => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100)
        if (percent < 100) entry.progress(percent)
      }
    })

    xhr.open("PUT", entry.meta.url, true)
    Object.entries(entry.meta.headers || {}).forEach(([name, value]) =>
      xhr.setRequestHeader(name, value)
    )
    xhr.send(entry.file)
  })
}
```

- [ ] **Step 2: Register it in `assets/js/app.js`**

Add the import next to the hook imports:

```javascript
import {S3PUT} from "./uploaders/s3_put"
```

and add `uploaders: {S3PUT},` to the LiveSocket options (the object that
already has `hooks: {...}`):

```javascript
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Sortable, DispatchMap, AddressMap, ClipboardCopy, PriceCountUp, ImageDownscale},
  uploaders: {S3PUT},
})
```

- [ ] **Step 3: Verify the bundle builds**

Run: `mix assets.build`
Expected: exits 0, no esbuild errors.

- [ ] **Step 4: Commit**

```bash
git add assets/js/uploaders/s3_put.js assets/js/app.js
git commit -m "feat(photos): S3PUT external uploader for presigned PUTs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Wire external uploads into both LiveViews

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex`
- Modify: `lib/mobile_car_wash_web/live/appointments_live.ex`
- Test: `test/mobile_car_wash_web/live/checklist_live_test.exs`, `test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`

**Interfaces:**
- Consumes: `PhotoUpload.external_uploads?/0`, `PhotoUpload.external_entry_meta/3`, `PhotoUpload.save_external_file/5`, `PhotoUpload.delete_file/1`, `parse_tile_name/1`, `save_tile_file/5`.
- Produces: `defp presign_photo(entry, socket)` (checklist), `defp presign_problem_photo(entry, socket)` (appointments); `save_tile_file/5` gains a `%{key: key}` clause; appointments' consume gains a `%{key: key}` clause.

- [ ] **Step 1: Write the failing preflight tests**

In `checklist_live_test.exs`, add a new describe block (module-level helpers
from earlier tasks are reused):

```elixir
  describe "external uploads (s3 backend)" do
    setup %{conn: conn} do
      prev_storage = Application.get_env(:mobile_car_wash, :photo_storage, :local)
      prev_key = Application.get_env(:ex_aws, :access_key_id)
      prev_secret = Application.get_env(:ex_aws, :secret_access_key)

      Application.put_env(:mobile_car_wash, :photo_storage, :s3)
      Application.put_env(:ex_aws, :access_key_id, "test-access-key")
      Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

      on_exit(fn ->
        Application.put_env(:mobile_car_wash, :photo_storage, prev_storage)
        Application.put_env(:ex_aws, :access_key_id, prev_key)
        Application.put_env(:ex_aws, :secret_access_key, prev_secret)
      end)

      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      {:ok, conn: sign_in(conn, user), appointment: appointment, checklist: checklist}
    end

    test "tile preflight returns S3PUT meta with a presigned key", %{
      conn: conn,
      checklist: checklist,
      appointment: appointment
    } do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      input = file_input(view, "#before-photo-form", :before_front, [jpeg_entry("front.jpg")])

      {:ok, resp} = preflight_upload(input)
      meta = resp.entries |> Map.values() |> hd()

      # NOTE: if these fail with a KeyError, the preflight reply
      # string-encodes keys — switch to meta["uploader"], meta["url"],
      # meta["key"] accordingly. Assert the same values either way.
      assert meta.uploader == "S3PUT"
      assert meta.url =~ "X-Amz-Expires=300"
      assert meta.key =~ "appointments/#{appointment.id}/before_"
    end
  end
```

In `appointments_photo_upload_test.exs`, add:

```elixir
  describe "external uploads (s3 backend)" do
    setup do
      prev_storage = Application.get_env(:mobile_car_wash, :photo_storage, :local)
      prev_key = Application.get_env(:ex_aws, :access_key_id)
      prev_secret = Application.get_env(:ex_aws, :secret_access_key)

      Application.put_env(:mobile_car_wash, :photo_storage, :s3)
      Application.put_env(:ex_aws, :access_key_id, "test-access-key")
      Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

      on_exit(fn ->
        Application.put_env(:mobile_car_wash, :photo_storage, prev_storage)
        Application.put_env(:ex_aws, :access_key_id, prev_key)
        Application.put_env(:ex_aws, :secret_access_key, prev_secret)
      end)

      :ok
    end

    test "problem-photo preflight returns S3PUT meta", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer.id)
      conn = sign_in(conn, customer)

      {:ok, view, _html} = live(conn, ~p"/appointments")

      view
      |> element("button[phx-value-id='#{appt.id}']", "Problem Area Photos")
      |> render_click()

      photo = %{
        name: "spot.jpg",
        content: <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 60_000),
        type: "image/jpeg"
      }

      input = file_input(view, "#photo-upload-form-#{appt.id}", :problem_photo_library, [photo])

      {:ok, resp} = preflight_upload(input)
      meta = resp.entries |> Map.values() |> hd()

      assert meta.uploader == "S3PUT"
      assert meta.key =~ "appointments/#{appt.id}/problem_area_"
    end
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`
Expected: FAIL — preflight returns channel-upload config (no `entries` meta with `uploader`), because no `external:` option is set.

- [ ] **Step 3: Implement**

3a. `checklist_live.ex` — make `tile_upload_opts/0` conditional and add the
presign callback plus the external save clause:

```elixir
  defp tile_upload_opts do
    base = [
      accept: ~w(.jpg .jpeg .png .webp),
      max_entries: 1,
      max_file_size: 10_000_000,
      auto_upload: true,
      progress: &handle_tile_progress/3
    ]

    if PhotoUpload.external_uploads?() do
      base ++ [external: &presign_photo/2]
    else
      base
    end
  end

  defp presign_photo(entry, socket) do
    {photo_type, _area} = parse_tile_name(entry.upload_config)

    case PhotoUpload.external_entry_meta(entry, socket.assigns.appointment.id, photo_type) do
      {:ok, meta} -> {:ok, meta, socket}
      {:error, reason} -> {:error, %{reason: inspect(reason)}, socket}
    end
  end
```

Add the external clause to `save_tile_file` (above the `%{path: path}` clause):

```elixir
  defp save_tile_file(%{key: key}, appointment_id, client_name, photo_type, area) do
    case PhotoUpload.save_external_file(appointment_id, key, client_name, photo_type,
           uploaded_by: :technician,
           car_part: area
         ) do
      {:ok, _photo} = ok ->
        ok

      {:error, reason} ->
        # The object is already in the bucket but has no DB row — remove
        # it best-effort so failed saves don't strand orphans.
        _ = PhotoUpload.delete_file(%{file_path: key})
        {:error, reason}
    end
  end
```

3b. `appointments_live.ex` — replace the two `allow_upload` pipes in `mount`
with a shared opts helper and add the presign callback + external consume
clause:

```elixir
      |> allow_upload(:problem_photo_camera, problem_photo_opts())
      |> allow_upload(:problem_photo_library, problem_photo_opts())
```

```elixir
  defp problem_photo_opts do
    base = [
      accept: ~w(.jpg .jpeg .png .webp),
      max_entries: 5,
      max_file_size: 10_000_000,
      auto_upload: true,
      progress: &handle_photo_progress/3
    ]

    if PhotoUpload.external_uploads?() do
      base ++ [external: &presign_problem_photo/2]
    else
      base
    end
  end

  defp presign_problem_photo(entry, socket) do
    case PhotoUpload.external_entry_meta(entry, socket.assigns.uploading_for, :problem_area) do
      {:ok, meta} -> {:ok, meta, socket}
      {:error, reason} -> {:error, %{reason: inspect(reason)}, socket}
    end
  end
```

In `handle_photo_progress/3`, the consume callback currently pattern-matches
`fn %{path: path} ->`. Extract the body into a helper with two clauses and
call it:

```elixir
      photo =
        consume_uploaded_entry(socket, entry, fn meta ->
          save_problem_photo(meta, appointment_id, entry, caption, car_part)
        end)
```

```elixir
  defp save_problem_photo(%{path: path}, appointment_id, entry, caption, car_part) do
    opts =
      [uploaded_by: :customer, caption: caption]
      |> then(fn o -> if car_part, do: o ++ [car_part: car_part], else: o end)

    case PhotoUpload.save_file(appointment_id, path, entry.client_name, :problem_area, opts) do
      {:ok, photo} -> {:ok, PhotoUpload.apply_url(photo)}
      other -> other
    end
  end

  defp save_problem_photo(%{key: key}, appointment_id, entry, caption, car_part) do
    opts =
      [uploaded_by: :customer, caption: caption]
      |> then(fn o -> if car_part, do: o ++ [car_part: car_part], else: o end)

    case PhotoUpload.save_external_file(appointment_id, key, entry.client_name, :problem_area, opts) do
      {:ok, photo} -> {:ok, PhotoUpload.apply_url(photo)}
      other -> other
    end
  end
```

(Keep the existing post-consume AI-subscribe and `update(:uploaded_photos, ...)`
code unchanged. Note `consume_uploaded_entry`'s callback here returns
`{:ok, photo}` — matching the current code's contract, where the consumed
value is the photo itself.)

- [ ] **Step 4: Run all four affected suites**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/checklist_live_test.exs test/mobile_car_wash_web/live/appointments_photo_upload_test.exs test/mobile_car_wash/operations/photo_upload_external_test.exs test/mobile_car_wash_web/components/photo_uploader_test.exs`
Expected: PASS. (The `:local` suites confirm nothing regressed; the `:s3` describes confirm the presigned preflight.)

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/checklist_live.ex lib/mobile_car_wash_web/live/appointments_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs test/mobile_car_wash_web/live/appointments_photo_upload_test.exs
git commit -m "feat(photos): direct-to-storage uploads on both photo surfaces

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Full-suite gate

**Files:**
- No source changes expected; fix anything the gate surfaces.

- [ ] **Step 1: Run the full precommit gate**

Run: `mix precommit`
Expected: exit 0, `0 failures` across the whole suite (~1400 tests). If a
failure appears in a file this plan touched, fix it here; if it's the known
flaky `AdminBlocksControllerTest` DBConnection sandbox contention, re-run to
confirm.

- [ ] **Step 2: Commit any gate fixes**

```bash
git status --short
# only if the gate required changes:
git add -A && git commit -m "fix(photos): address precommit gate findings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Post-implementation (not part of the coding tasks)

- Deploy checklist lives in the spec: set CORS on the Space (origin = prod
  app origin, method PUT, header content-type) before releasing.
- Manual phone verification per the spec's checklist — the S3PUT JS path
  and real CORS behavior have no automated coverage.
