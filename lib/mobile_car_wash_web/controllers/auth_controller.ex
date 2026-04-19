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

  @doc """
  Re-sends the email verification link. Triggered by the soft-gate
  banner shown in the authenticated layout. Silently no-ops for
  already-verified / signed-out visitors so we don't leak account
  state through distinct flash messages.
  """
  def resend_verification(conn, _params) do
    case current_customer(conn) do
      %{email_verified_at: nil, id: customer_id} ->
        %{"customer_id" => customer_id}
        |> MobileCarWash.Notifications.VerificationEmailWorker.new()
        |> Oban.insert!()

        resend_reply(conn)

      _ ->
        resend_reply(conn)
    end
  end

  defp resend_reply(conn) do
    conn
    |> put_flash(:info, "Verification email sent. Check your inbox.")
    |> redirect(to: redirect_back(conn))
  end

  defp current_customer(conn) do
    cond do
      user = conn.assigns[:current_user] -> user
      user = conn.assigns[:current_customer] -> user
      true -> customer_from_session(conn)
    end
  end

  defp customer_from_session(conn) do
    case get_session(conn, "customer_token") do
      token when is_binary(token) ->
        with {:ok, %{"sub" => subject}, _} <-
               AshAuthentication.Jwt.verify(token, :mobile_car_wash),
             {:ok, customer} <-
               AshAuthentication.subject_to_user(subject, MobileCarWash.Accounts.Customer) do
          customer
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp redirect_back(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)

        if uri.host in [nil, conn.host] do
          uri.path || "/"
        else
          "/"
        end

      _ ->
        "/"
    end
  end
end
