defmodule MobileCarWashWeb.CatalogChannel do
  use Phoenix.Channel

  alias Phoenix.PubSub

  @impl true
  def join("catalog", _payload, socket) do
    PubSub.subscribe(MobileCarWash.PubSub, "catalog:updates")
    {:ok, %{}, socket}
  end

  @impl true
  def handle_info({event, payload}, socket) when event in [:services_updated, :plans_updated] do
    push(socket, Atom.to_string(event), payload)
    {:noreply, socket}
  end
end
