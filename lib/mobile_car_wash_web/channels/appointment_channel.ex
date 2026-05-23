defmodule MobileCarWashWeb.AppointmentChannel do
  use Phoenix.Channel

  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.Appointment

  require Ash.Query

  @impl true
  def join("appointment:" <> appointment_id, _payload, socket) do
    customer = socket.assigns.current_customer

    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         true <- owns?(customer, appointment) do
      MobileCarWash.Scheduling.AppointmentTracker.subscribe(appointment_id)
      {:ok, %{appointment_id: appointment_id}, assign(socket, :appointment_id, appointment_id)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({:appointment_update, %{event: event} = payload}, socket) do
    push(socket, Atom.to_string(event), Map.delete(payload, :event))
    {:noreply, socket}
  end

  defp owns?(%{role: :admin}, _appointment), do: true
  defp owns?(%{id: id}, %{customer_id: id}), do: true

  defp owns?(customer, %{technician_id: technician_id}) do
    case find_tech(customer) do
      %Technician{id: ^technician_id} -> true
      _ -> false
    end
  end

  defp find_tech(customer) do
    Technician
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn t -> t.user_account_id == customer.id || t.name == customer.name end)
  end
end
