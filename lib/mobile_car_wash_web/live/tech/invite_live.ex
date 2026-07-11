defmodule MobileCarWashWeb.Tech.InviteLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.TechInvites

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case TechInvites.pending_invite(token) do
      {:ok, invite} ->
        {:ok,
         assign(socket,
           page_title: "Set Password",
           token: token,
           invite: invite,
           error: nil
         ), layout: false}

      {:error, _reason} ->
        {:ok,
         assign(socket,
           page_title: "Invite Unavailable",
           token: token,
           invite: nil,
           error: nil
         ), layout: false}
    end
  end

  @impl true
  def handle_event(
        "accept",
        %{"invite" => %{"password" => password, "password_confirmation" => confirmation}},
        socket
      ) do
    case TechInvites.accept_invite(socket.assigns.token, password, confirmation) do
      {:ok, _accepted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Technician account set up. Sign in to continue.")
         |> redirect(to: ~p"/sign-in")}

      {:error, _reason} ->
        {:noreply, assign(socket, error: "Could not set password.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main class="mx-auto flex min-h-[calc(100vh-8rem)] w-full max-w-3xl items-center px-4 py-10">
        <section class="w-full rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8">
          <div :if={@invite} class="space-y-6">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.24em] text-primary/80">
                Technician invite
              </p>
              <h1 class="text-3xl font-semibold text-base-content">Set password</h1>
              <p class="text-sm leading-6 text-base-content/70">
                Welcome, {@invite.customer.name}. Finish setup to activate your technician account.
              </p>
            </div>

            <div
              :if={@error}
              class="rounded-2xl border border-error/25 bg-error/10 px-4 py-3 text-sm font-medium text-error"
            >
              {@error}
            </div>

            <form id="tech-invite-form" phx-submit="accept" class="space-y-4">
              <div class="form-control">
                <label class="label label-text text-sm font-medium">Password</label>
                <input
                  type="password"
                  name="invite[password]"
                  class="input input-bordered w-full"
                  autocomplete="new-password"
                  required
                />
              </div>

              <div class="form-control">
                <label class="label label-text text-sm font-medium">Confirm password</label>
                <input
                  type="password"
                  name="invite[password_confirmation]"
                  class="input input-bordered w-full"
                  autocomplete="new-password"
                  required
                />
              </div>

              <button type="submit" class="btn btn-primary w-full">Set password</button>
            </form>
          </div>

          <div :if={!@invite} class="space-y-4 text-center">
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-error/80">
              Invite unavailable
            </p>
            <h1 class="text-3xl font-semibold text-base-content">
              This setup link is invalid or expired.
            </h1>
            <p class="text-sm leading-6 text-base-content/70">
              Ask an admin to send a new technician setup link.
            </p>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
