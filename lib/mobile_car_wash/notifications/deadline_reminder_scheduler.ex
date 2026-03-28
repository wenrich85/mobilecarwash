defmodule MobileCarWash.Notifications.DeadlineReminderScheduler do
  @moduledoc """
  Daily Oban cron job that checks for upcoming formation/compliance deadlines.
  Runs at 8am daily. Enqueues DeadlineReminderWorker jobs for tasks
  due in 7 days and 1 day.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 1

  alias MobileCarWash.Compliance.FormationTask
  alias MobileCarWash.Notifications.DeadlineReminderWorker

  require Ash.Query

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()

    # Find tasks due in exactly 7 days
    seven_days = Date.add(today, 7)
    enqueue_reminders_for_date(seven_days, 7)

    # Find tasks due in exactly 1 day
    one_day = Date.add(today, 1)
    enqueue_reminders_for_date(one_day, 1)

    :ok
  end

  defp enqueue_reminders_for_date(target_date, days_before) do
    tasks =
      FormationTask
      |> Ash.Query.filter(due_date == ^target_date and status != :completed)
      |> Ash.read!()

    for task <- tasks do
      %{task_id: task.id, days_before: days_before}
      |> DeadlineReminderWorker.new(queue: :notifications)
      |> Oban.insert()
    end
  end
end
