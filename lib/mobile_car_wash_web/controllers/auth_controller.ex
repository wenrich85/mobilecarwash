defmodule MobileCarWashWeb.AuthController do
  use MobileCarWashWeb, :controller
  use AshAuthentication.Phoenix.Controller, otp_app: :mobile_car_wash

  def success(conn, _activity, user, _token) do
    redirect_path =
      case user.role do
        :admin -> ~p"/admin"
        :technician -> ~p"/tech"
        _ -> ~p"/"
      end

    # Store the token in the token table so load_from_session can verify it.
    # Without this, the load_from_session plug deletes the session key because
    # the JTI isn't found in the token table with purpose "user".
    if user.__metadata__[:token] do
      AshAuthentication.TokenResource.Actions.store_token(
        MobileCarWash.Accounts.Token,
        %{"token" => user.__metadata__.token, "purpose" => "user"},
        []
      )
    end

    conn
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: redirect_path)
  end

  @doc """
  Handles the sign_in_with_token callback as a regular controller action.
  Bypasses the StrategyRouter forward which caused session cookie scoping issues.
  """
  def sign_in_with_token(conn, %{"token" => token}) do
    case AshAuthentication.Jwt.verify(token, :mobile_car_wash) do
      {:ok, %{"sub" => subject}, _} ->
        case AshAuthentication.subject_to_user(subject, MobileCarWash.Accounts.Customer) do
          {:ok, _user} ->
            strategy = AshAuthentication.Info.strategy!(MobileCarWash.Accounts.Customer, :password)

            case AshAuthentication.Strategy.action(strategy, :sign_in_with_token, %{"token" => token}) do
              {:ok, authenticated_user} ->
                success(conn, {:password, :sign_in_with_token}, authenticated_user, nil)

              {:error, _} ->
                failure(conn, nil, "Authentication failed")
            end

          _ ->
            failure(conn, nil, "User not found")
        end

      _ ->
        failure(conn, nil, "Invalid token")
    end
  end

  def sign_in_with_token(conn, _params) do
    failure(conn, nil, "Missing token")
  end

  def failure(conn, activity, reason) do
    require Logger
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    Logger.warning("Auth failure: activity=#{inspect(activity)} ip=#{ip} reason=#{inspect(reason)}")

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

  @doc """
  One-shot email verification link handler. Reads the token from the
  query string, looks up the customer by subject, and runs the
  `:verify_email` action. Outcomes surface as a flash + redirect —
  soft-gate semantics, no blocking page.
  """
  def verify_email(conn, %{"token" => token}) when is_binary(token) do
    case AshAuthentication.Jwt.peek(token) do
      {:ok, %{"sub" => subject}} ->
        case AshAuthentication.subject_to_user(subject, MobileCarWash.Accounts.Customer) do
          {:ok, customer} ->
            customer
            |> Ash.Changeset.for_update(:verify_email, %{token: token})
            |> Ash.update(authorize?: false)
            |> case do
              {:ok, _verified} ->
                conn
                |> put_flash(:info, "Email verified. Thanks!")
                |> redirect(to: ~p"/")

              {:error, _changeset} ->
                conn
                |> put_flash(:error, "This verification link is invalid or expired.")
                |> redirect(to: ~p"/")
            end

          _ ->
            conn
            |> put_flash(:error, "This verification link is invalid or expired.")
            |> redirect(to: ~p"/")
        end

      _ ->
        conn
        |> put_flash(:error, "This verification link is invalid or expired.")
        |> redirect(to: ~p"/")
    end
  end

  def verify_email(conn, _params) do
    conn
    |> put_flash(:error, "Missing verification token.")
    |> redirect(to: ~p"/")
  end
end
