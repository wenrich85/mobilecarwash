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

  test "exceptions include unassigned pending jobs and flagged customers" do
    unassigned = appointment(%{id: "unassigned", status: :pending, technician_id: nil})

    flagged =
      appointment(%{
        id: "flagged",
        status: :confirmed,
        technician_id: "tech-1",
        customer_id: "cust-flag"
      })

    exceptions =
      DispatchPresenter.exceptions([unassigned, flagged],
        flagged_customer_ids: MapSet.new(["cust-flag"]),
        tech_requests: %{},
        progress_by_appointment: %{},
        photo_counts_by_appointment: %{}
      )

    assert Enum.any?(exceptions, &(&1.appointment_id == "unassigned" and &1.kind == :unassigned))
    assert Enum.any?(exceptions, &(&1.appointment_id == "flagged" and &1.kind == :booking_flag))
  end

  test "technician_workload marks current activity and assignment counts" do
    techs = [
      %{id: "tech-1", name: "Ava", active: true, status: :available, zone: :north},
      %{id: "tech-2", name: "Noah", active: true, status: :on_break, zone: nil}
    ]

    appointments = [
      appointment(%{id: "a1", status: :confirmed, technician_id: "tech-1"}),
      appointment(%{id: "a2", status: :in_progress, technician_id: "tech-1"}),
      appointment(%{id: "a3", status: :confirmed, technician_id: "tech-2"})
    ]

    workloads =
      DispatchPresenter.technician_workload(techs, appointments, %{
        "tech-1" => %{status: :in_progress}
      })

    assert [%{id: "tech-1", assigned_count: 2, active?: true}, %{id: "tech-2", assigned_count: 1}] =
             workloads
  end
end
