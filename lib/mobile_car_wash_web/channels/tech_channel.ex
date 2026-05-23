defmodule MobileCarWashWeb.TechChannel do
  use Phoenix.Channel

  alias MobileCarWash.Operations.{Technician, TechnicianTracker}
  alias MobileCarWash.Scheduling.AppointmentTracker

  @impl true
  def join("tech:" <> tech_id, _payload, socket) do
    customer = socket.assigns.current_customer

    case find_tech(customer) do
      %Technician{id: ^tech_id} when customer.role in [:technician, :admin] ->
        AppointmentTracker.subscribe_to_tech_assignments(tech_id)
        TechnicianTracker.subscribe(tech_id)
        {:ok, %{tech_id: tech_id}, assign(socket, :tech_id, tech_id)}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({:appointment_assigned, appointment_id}, socket) do
    push(socket, "appointment_assigned", %{appointment_id: appointment_id})
    {:noreply, socket}
  end

  def handle_info({:technician_status, payload}, socket) do
    push(socket, "status_changed", payload)
    {:noreply, socket}
  end

  defp find_tech(customer) do
    Technician
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn t -> t.user_account_id == customer.id || t.name == customer.name end)
  end
end
