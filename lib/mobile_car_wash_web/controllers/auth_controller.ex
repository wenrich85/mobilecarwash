defmodule MobileCarWashWeb.AuthController do
  use MobileCarWashWeb, :controller
  use AshAuthentication.Phoenix.Controller, otp_app: :mobile_car_wash

  def success(conn, _activity, user, _token) do
    conn
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: ~p"/")
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Authentication failed. Please check your credentials.")
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    conn
    |> clear_session(:mobile_car_wash)
    |> put_flash(:info, "Signed out successfully.")
    |> redirect(to: ~p"/")
  end
end
