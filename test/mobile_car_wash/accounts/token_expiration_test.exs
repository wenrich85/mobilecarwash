defmodule MobileCarWash.Accounts.TokenExpirationTest do
  @moduledoc """
  SECURITY_AUDIT_REPORT MEDIUM #1: pin the two guarantees that together
  make token expiration meaningful:

    1. The Customer resource configures a concrete `token_lifetime` (we
       use 7 days). If someone silently drops or relaxes this, the first
       test catches it.
    2. A JWT signed with the correct secret but an `exp` claim in the
       past is rejected by `AshAuthentication.Jwt.verify/2`. If upstream
       behaviour ever regresses or our signer config drifts, the second
       test catches it.
  """
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer

  describe "resource-level token lifetime config" do
    test "Customer declares a 7-day token lifetime" do
      lifetime =
        AshAuthentication.Info.authentication_tokens_token_lifetime!(Customer)

      assert lifetime == {7, :days},
             """
             Customer.token_lifetime changed. If the shortening is intentional
             update this test; if it was accidental restore the previous value.
             (The audit report recommends < 7 days for access tokens; sliding
             expiration / refresh tokens are tracked as MEDIUM #5.)
             """
    end
  end

  describe "AshAuthentication.Jwt.verify/2 rejects expired tokens" do
    setup do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "token-exp-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Token Exp",
          phone: "+15125551900"
        })
        |> Ash.create()

      %{customer: customer}
    end

    test "a freshly-minted token verifies", %{customer: customer} do
      {:ok, token, _claims} =
        AshAuthentication.Jwt.token_for_user(customer, %{}, resource: Customer)

      assert {:ok, _claims, _resource} =
               AshAuthentication.Jwt.verify(token, :mobile_car_wash)
    end

    test "a token signed with the same secret but exp in the past is rejected",
         %{customer: customer} do
      expired_token = sign_token_with_past_exp(customer)

      assert :error = AshAuthentication.Jwt.verify(expired_token, :mobile_car_wash)
    end

    test "tampering with a valid token's payload invalidates it",
         %{customer: customer} do
      {:ok, good_token, _} =
        AshAuthentication.Jwt.token_for_user(customer, %{}, resource: Customer)

      # Flip a byte in the signature — the final segment of a JWT.
      [header, payload, signature] = String.split(good_token, ".")
      tampered_signature = flip_first_char(signature)
      tampered = Enum.join([header, payload, tampered_signature], ".")

      assert :error = AshAuthentication.Jwt.verify(tampered, :mobile_car_wash)
    end
  end

  # --- Test helpers ---

  # Forges a JWT signed with the real signing secret but with an `exp`
  # claim 1 hour in the past. Mirrors the claims AshAuthentication
  # normally sets so nothing except the expiration fails validation.
  defp sign_token_with_past_exp(customer) do
    secret = Application.fetch_env!(:mobile_car_wash, :token_signing_secret)
    signer = Joken.Signer.create("HS256", secret)

    now = System.system_time(:second)
    past_exp = now - 3_600

    subject = AshAuthentication.user_to_subject(customer)

    claims = %{
      "sub" => subject,
      "iat" => past_exp - 86_400,
      "nbf" => past_exp - 86_400,
      "exp" => past_exp,
      "jti" => Ecto.UUID.generate(),
      "aud" => "~> 2.0",
      "iss" => "AshAuthentication v#{Application.spec(:ash_authentication, :vsn)}",
      "purpose" => "user"
    }

    {:ok, token, _claims} = Joken.generate_and_sign(%{}, claims, signer)
    token
  end

  defp flip_first_char(<<first::utf8, rest::binary>>) do
    # "a" <-> "b" is enough to invalidate the signature without breaking
    # base64 URL-safe charset rules.
    replacement = if first == ?a, do: ?b, else: ?a
    <<replacement::utf8>> <> rest
  end
end
