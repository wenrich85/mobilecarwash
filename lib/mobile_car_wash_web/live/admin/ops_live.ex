defmodule MobileCarWashWeb.Admin.OpsLive do
  @moduledoc """
  Operational health dashboard — per-queue Oban depths, recent job
  failures, and basic runtime stats. The owner-facing equivalent of
  a k8s ops page.

  Data comes from Oban's `oban_jobs` table directly via Ecto (works
  in both :inline testing mode and :basic prod mode).
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Repo

  import Ecto.Query

  # Keep in sync with config/config.exs Oban queues list.
  @queues ~w(default notifications billing analytics maintenance ai)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Operations")
     |> load_all()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_all(socket)}
  end

  defp load_all(socket) do
    socket
    |> assign(queue_depths: queue_depths())
    |> assign(recent_failures: recent_failures(10))
    |> assign(runtime: runtime_stats())
    |> assign(refreshed_at: DateTime.utc_now())
  end

  # --- Oban stats ---

  defp queue_depths do
    # Rows grouped by (queue, state). A missing (queue, state) means 0.
    rows =
      from(j in "oban_jobs",
        group_by: [j.queue, j.state],
        select: {j.queue, j.state, count(j.id)}
      )
      |> Repo.all()
      |> Enum.group_by(fn {queue, _state, _n} -> queue end, fn {_q, state, n} -> {state, n} end)

    Enum.map(@queues, fn queue ->
      by_state = Map.get(rows, queue, []) |> Map.new()

      %{
        queue: queue,
        available: Map.get(by_state, "available", 0),
        executing: Map.get(by_state, "executing", 0),
        retryable: Map.get(by_state, "retryable", 0),
        scheduled: Map.get(by_state, "scheduled", 0),
        completed: Map.get(by_state, "completed", 0),
        discarded: Map.get(by_state, "discarded", 0)
      }
    end)
  end

  defp recent_failures(limit) do
    query =
      from j in "oban_jobs",
        where: j.state in ["discarded", "retryable"],
        order_by: [desc: j.attempted_at],
        limit: ^limit,
        select: %{
          id: j.id,
          worker: j.worker,
          queue: j.queue,
          state: j.state,
          attempt: j.attempt,
          max_attempts: j.max_attempts,
          attempted_at: j.attempted_at
        }

    Repo.all(query)
  end

  # --- Runtime stats ---

  defp runtime_stats do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    memory_bytes = :erlang.memory(:total)
    proc_count = :erlang.system_info(:process_count)
    schedulers = :erlang.system_info(:schedulers_online)

    %{
      uptime_human: format_duration(uptime_ms),
      memory_mb: Float.round(memory_bytes / 1_048_576, 1),
      process_count: proc_count,
      schedulers: schedulers,
      otp_release: :erlang.system_info(:otp_release) |> to_string(),
      node: node() |> to_string()
    }
  end

  defp format_duration(ms) do
    total_seconds = div(ms, 1000)
    days = div(total_seconds, 86_400)
    hours = div(rem(total_seconds, 86_400), 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m #{seconds}s"
      true -> "#{seconds}s"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold">Operations</h1>
          <p class="text-base-content/80">
            Queue depths, recent job failures, runtime snapshot.
          </p>
        </div>
        <button id="refresh-ops" phx-click="refresh" class="btn btn-ghost btn-sm">
          Refresh
        </button>
      </div>
      
    <!-- Runtime -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">Uptime</div>
          <div class="stat-value text-primary">{@runtime.uptime_human}</div>
        </div>
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">Memory</div>
          <div class="stat-value text-secondary">{@runtime.memory_mb} MB</div>
        </div>
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">Processes</div>
          <div class="stat-value">{@runtime.process_count}</div>
        </div>
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">Schedulers</div>
          <div class="stat-value">{@runtime.schedulers}</div>
        </div>
      </div>
      
    <!-- Queue depths -->
      <div class="card bg-base-100 border border-base-300 mb-8">
        <div class="card-body">
          <h2 class="card-title">Oban queue depths</h2>
          <p class="text-sm text-base-content/60 mb-2">
            <code>available</code>
            = waiting to run · <code>executing</code>
            = running now · <code>retryable</code>
            = failed, will retry · <code>scheduled</code>
            = will run later · <code>discarded</code>
            = permanently failed
          </p>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Queue</th>
                  <th class="text-right">Available</th>
                  <th class="text-right">Executing</th>
                  <th class="text-right">Retryable</th>
                  <th class="text-right">Scheduled</th>
                  <th class="text-right">Discarded</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={q <- @queue_depths} class="hover">
                  <td class="font-medium">{q.queue}</td>
                  <td class="text-right">{q.available}</td>
                  <td class="text-right">{q.executing}</td>
                  <td class={["text-right", q.retryable > 0 && "text-warning font-semibold"]}>
                    {q.retryable}
                  </td>
                  <td class="text-right">{q.scheduled}</td>
                  <td class={["text-right", q.discarded > 0 && "text-error font-semibold"]}>
                    {q.discarded}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
      
    <!-- Recent failures -->
      <div class="card bg-base-100 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Recent job failures</h2>

          <div :if={@recent_failures == []} class="text-center py-6 text-success">
            No retries or discards in the job log — clean slate.
          </div>

          <table :if={@recent_failures != []} class="table table-sm">
            <thead>
              <tr>
                <th>When</th>
                <th>Worker</th>
                <th>Queue</th>
                <th>State</th>
                <th class="text-right">Attempts</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={j <- @recent_failures} class="hover">
                <td class="text-sm text-base-content/70">
                  {if j.attempted_at,
                    do: Calendar.strftime(j.attempted_at, "%b %d %H:%M:%S"),
                    else: "—"}
                </td>
                <td class="truncate"><code>{j.worker}</code></td>
                <td>{j.queue}</td>
                <td>
                  <span class={"badge badge-sm " <> if(j.state == "discarded", do: "badge-error", else: "badge-warning")}>
                    {j.state}
                  </span>
                </td>
                <td class="text-right">{j.attempt} / {j.max_attempts}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <p class="text-xs text-base-content/50 mt-4">
        Refreshed {Calendar.strftime(@refreshed_at, "%H:%M:%S UTC")} · node
        <code>{@runtime.node}</code>
        · OTP <code>{@runtime.otp_release}</code>
      </p>
    </div>
    """
  end
end
