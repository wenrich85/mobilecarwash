defmodule MobileCarWashWeb.UserSocket do
  use Phoenix.Socket

  channel "appointment:*", MobileCarWashWeb.AppointmentChannel
  channel "tech:*", MobileCarWashWeb.TechChannel
  channel "catalog", MobileCarWashWeb.CatalogChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case AshAuthentication.Jwt.verify(token, :mobile_car_wash) do
      {:ok, %{"sub" => subject}, _} ->
        case AshAuthentication.subject_to_user(subject, MobileCarWash.Accounts.Customer) do
          {:ok, customer} -> {:ok, assign(socket, :current_customer, customer)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%{assigns: %{current_customer: %{id: id}}}), do: "customer_socket:#{id}"
  def id(_socket), do: nil
end
