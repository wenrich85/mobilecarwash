defmodule MobileCarWash.Notifications.DeadlineReminderWorker do
  @moduledoc """
  Oban worker that sends deadline reminder emails to the admin
  for upcoming formation/compliance tasks.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Compliance.{FormationTask, TaskCategory}
  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Mailer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id, "days_before" => days_before}}) do
    with {:ok, task} <- Ash.get(FormationTask, task_id),
         false <- task.status == :completed,
         {:ok, category} <- Ash.get(TaskCategory, task.category_id) do
      admin_emails = Application.get_env(:mobile_car_wash, :admin_emails, [])

      for admin_email <- admin_emails do
        email = Email.deadline_reminder(task, category, days_before, admin_email)

        case Mailer.deliver(email) do
          {:ok, _} ->
            Logger.info("Deadline reminder sent for task '#{task.name}' (#{days_before} days)")

          {:error, reason} ->
            Logger.error("Failed to send deadline reminder: #{inspect(reason)}")
        end
      end

      :ok
    else
      true ->
        Logger.info("Skipping reminder for completed task #{task_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to load task for deadline reminder: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
