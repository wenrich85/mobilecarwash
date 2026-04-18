defmodule MobileCarWashWeb.Auth.SignInLive do
  use MobileCarWashWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sign In")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-base-200">
      <div class="card bg-base-100 shadow-xl w-full max-w-md">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">Sign In</h2>

          <div class="alert alert-info mb-4">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="h-6 w-6 shrink-0 stroke-current"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              >
              </path>
            </svg>
            <div>
              <h3 class="font-bold">Authentication Required</h3>
              <div class="text-xs">Sign in to continue. Use the mobile app or contact support for sign-up.</div>
            </div>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-semibold">Email</span>
            </label>
            <input
              type="email"
              placeholder="your@email.com"
              class="input input-bordered"
              disabled
            />
            <p class="text-xs text-base-content/80 mt-1">
              Sign-in is handled through the mobile app or via email link.
            </p>
          </div>

          <div class="divider my-2"></div>

          <p class="text-sm text-center text-base-content/80">
            If you need help signing in, contact support.
          </p>

          <div class="card-actions justify-center mt-6">
            <.link navigate={~p"/"} class="btn btn-outline">
              Back to Home
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
