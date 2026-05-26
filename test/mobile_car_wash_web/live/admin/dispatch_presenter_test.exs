defmodule MobileCarWashWeb.Admin.DispatchPresenterTest do
  use ExUnit.Case, async: true

  alias MobileCarWashWeb.Admin.DispatchPresenter

  defp appointment(attrs) do
    Map.merge(
      %{
        id: "appt-1",
        status: :pending,
        technician_id: nil,
        customer_id: "cust-1",
        service_type_id: "svc-1",
        scheduled_at: ~U[2026-05-25 15:00:00Z]
      },
      attrs
    )
  end

  test "metrics summarize live dispatch state" do
    appointments = [
      appointment(%{id: "pending", status: :pending}),
      appointment(%{id: "confirmed", status: :confirmed, technician_id: "tech-1"}),
      appointment(%{id: "active", status: :in_progress, technician_id: "tech-2"}),
      appointment(%{id: "done", status: :completed, technician_id: "tech-3"})
    ]

    technicians = [
      %{id: "tech-1", active: true, status: :available},
      %{id: "tech-2", active: true, status: :on_break},
      %{id: "tech-3", active: false, status: :off_duty}
    ]

    assert DispatchPresenter.metrics(appointments, technicians, []) == %{
             total: 4,
             in_progress: 1,
             ready_to_assign: 1,
             completed: 1,
             on_duty: 1,
             exceptions: 0
           }
  end

  test "assignment_queue returns pending and confirmed jobs sorted by schedule" do
    later = appointment(%{id: "later", status: :pending, scheduled_at: ~U[2026-05-25 17:00:00Z]})

    sooner =
      appointment(%{id: "sooner", status: :confirmed, scheduled_at: ~U[2026-05-25 14:00:00Z]})

    complete =
      appointment(%{id: "complete", status: :completed, scheduled_at: ~U[2026-05-25 13:00:00Z]})

    assert [%{id: "sooner"}, %{id: "later"}] =
             DispatchPresenter.assignment_queue([later, sooner, complete])
  end
end
