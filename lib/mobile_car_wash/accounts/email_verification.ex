defmodule MobileCarWash.Accounts.EmailVerification do
  @moduledoc """
  Mints and verifies one-shot email-verification JWTs.

  The token is intentionally distinct from the normal auth token:
    * purpose claim = "email_verification" — rejected by the regular
      auth plugs, so it can't be used as a session.
    * 24-hour lifetime by default.
    * embeds the email address at mint time, so changing the email
      after the fact invalidates the outstanding link.

  The verification itself is handled by the `:verify_email` Ash action
  on `Customer`, which calls `verify_token/2` below.
  """

  require Logger

  @default_lifetime_seconds 24 * 3600

  @spec mint_token(Ash.Resource.record(), keyword) :: String.t()
  def mint_token(customer, opts \\ []) do
    secret = signing_secret!()
    signer = Joken.Signer.create("HS256", secret)

    now = System.system_time(:second)
    expires_in = Keyword.get(opts, :expires_in, @default_lifetime_seconds)

    claims = %{
      "sub" => AshAuthentication.user_to_subject(customer),
      "email" => to_string(customer.email),
      "purpose" => "email_verification",
      "iat" => now,
      "nbf" => now,
      "exp" => now + expires_in,
      "jti" => Ecto.UUID.generate()
    }

    {:ok, token, _} = Joken.generate_and_sign(%{}, claims, signer)
    token
  end

  @doc """
  Verifies a token against a customer record. Returns `:ok` when the
  token is valid, otherwise `{:error, reason}` where reason is one of
  `:expired`, `:wrong_purpose`, `:sub_mismatch`, `:email_mismatch`,
  `:invalid`.
  """
  @spec verify_token(Ash.Resource.record(), String.t()) ::
          :ok | {:error, atom()}
  def verify_token(customer, token) when is_binary(token) do
    signer = Joken.Signer.create("HS256", signing_secret!())

    with {:ok, claims} <- Joken.verify_and_validate(token_config(), token, signer),
         :ok <- check_purpose(claims),
         :ok <- check_subject(customer, claims),
         :ok <- check_email(customer, claims) do
      :ok
    else
      {:error, [message: "Invalid token", claim: "exp", claim_val: _]} ->
        {:error, :expired}

      {:error, reason} when is_atom(reason) ->
        {:error, reason}

      _ ->
        {:error, :invalid}
    end
  end

  def verify_token(_customer, _), do: {:error, :invalid}

  defp signing_secret! do
    Application.fetch_env!(:mobile_car_wash, :token_signing_secret)
  end

  defp token_config do
    Joken.Config.default_claims(skip: [:iss, :aud])
  end

  defp check_purpose(%{"purpose" => "email_verification"}), do: :ok
  defp check_purpose(_), do: {:error, :wrong_purpose}

  defp check_subject(customer, %{"sub" => sub}) do
    if sub == AshAuthentication.user_to_subject(customer) do
      :ok
    else
      {:error, :sub_mismatch}
    end
  end

  defp check_subject(_, _), do: {:error, :invalid}

  defp check_email(customer, %{"email" => email}) do
    if email == to_string(customer.email) do
      :ok
    else
      {:error, :email_mismatch}
    end
  end

  defp check_email(_, _), do: {:error, :invalid}
end
