defmodule MobileCarWash.Accounts.Customer do
  @moduledoc """
  Customer resource with authentication via email + password.
  Extensible for OAuth and magic link in future.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table("customers")
    repo(MobileCarWash.Repo)
  end

  authentication do
    tokens do
      enabled?(true)
      token_resource(MobileCarWash.Accounts.Token)
      require_token_presence_for_authentication?(true)
      token_lifetime({7, :days})

      signing_secret(fn _, _ ->
        Application.fetch_env(:mobile_car_wash, :token_signing_secret)
      end)
    end

    strategies do
      password :password do
        identity_field(:email)
        hashed_password_field(:hashed_password)

        register_action_accept([
          :name,
          :phone,
          :sms_opt_in,
          :push_opt_in,
          :utm_source,
          :utm_medium,
          :utm_campaign,
          :utm_content,
          :referrer,
          :acquired_at,
          :acquired_channel_id
        ])
      end
    end
  end

  policies do
    # Authentication actions — bypass so they short-circuit before actor-based policies.
    # These are :read/:create actions with no actor present during sign-in/registration.
    bypass action(:register_with_password) do
      authorize_if(always())
    end

    bypass action(:sign_in_with_password) do
      authorize_if(always())
    end

    bypass action(:sign_in_with_token) do
      authorize_if(always())
    end

    bypass action(:get_by_subject) do
      authorize_if(always())
    end

    bypass action(:by_email) do
      authorize_if(always())
    end

    bypass action(:create_guest) do
      authorize_if(always())
    end

    bypass action(:by_referral_code) do
      authorize_if(always())
    end

    # Customers can read and update their own record; admins can read/update anyone
    policy action_type(:read) do
      authorize_if(expr(id == ^actor(:id)))
      authorize_if(expr(^actor(:role) == :admin))
    end

    policy action_type(:update) do
      authorize_if(expr(id == ^actor(:id)))
      authorize_if(expr(^actor(:role) == :admin))
    end

    # Deletion is admin-only
    policy action_type(:destroy) do
      authorize_if(expr(^actor(:role) == :admin))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :phone, :string do
      public?(true)
    end

    attribute :role, :atom do
      constraints(one_of: [:customer, :technician, :admin, :guest])
      default(:customer)
      allow_nil?(false)
      public?(true)
    end

    attribute :stripe_customer_id, :string do
      public?(true)
    end

    attribute :sms_opt_in, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    # Server-side gate for APNs push. Defaults to true because iOS's
    # UNUserNotificationCenter permission already gates delivery client-side;
    # this lets a user revoke in-app without opening iOS Settings.
    attribute :push_opt_in, :boolean do
      default(true)
      allow_nil?(false)
      public?(true)
    end

    attribute :referral_code, :string do
      public?(true)
    end

    attribute :referral_credit_cents, :integer do
      default(0)
      allow_nil?(false)
      public?(true)
    end

    # Stamped the first (and only) time a referrer is credited for
    # bringing this customer in. Guards against double-rewarding the
    # same referral across repeated :succeeded payment hooks.
    attribute :referral_reward_issued_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :hashed_password, :string do
      allow_nil?(true)
      sensitive?(true)
    end

    # Nil until the user clicks the link in their signup email. Soft
    # gate — unverified accounts are nudged via banner but not blocked
    # from booking, paying, etc. (SECURITY_AUDIT_REPORT MEDIUM #6.)
    attribute :email_verified_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    # Marketing attribution (first-touch). Stamped by the
    # CaptureAttribution plug + register-flow changes; never
    # overwritten by later visits. Drives the CAC / LTV per-channel
    # rollups on /admin/marketing.
    attribute(:utm_source, :string, public?: true)
    attribute(:utm_medium, :string, public?: true)
    attribute(:utm_campaign, :string, public?: true)
    attribute(:utm_content, :string, public?: true)
    attribute(:referrer, :string, public?: true)

    attribute :acquired_at, :utc_datetime_usec do
      public?(true)
      default(&DateTime.utc_now/0)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :referred_by, __MODULE__, allow_nil?: true

    belongs_to :acquired_channel, MobileCarWash.Marketing.AcquisitionChannel do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_email, [:email])
    identity(:unique_referral_code, [:referral_code])
  end

  validations do
    validate(
      fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :password) do
          nil ->
            :ok

          password when is_binary(password) ->
            cond do
              String.length(password) < 10 ->
                {:error, field: :password, message: "must be at least 10 characters"}

              not String.match?(password, ~r/[A-Z]/) ->
                {:error, field: :password, message: "must contain at least one uppercase letter"}

              not String.match?(password, ~r/[a-z]/) ->
                {:error, field: :password, message: "must contain at least one lowercase letter"}

              not String.match?(password, ~r/[0-9]/) ->
                {:error, field: :password, message: "must contain at least one number"}

              true ->
                :ok
            end

          _ ->
            :ok
        end
      end,
      on: [:create]
    )

    # SECURITY_AUDIT_REPORT MEDIUM #3: reject obviously-invalid email
    # strings at the resource level. Not a full RFC check — just enough to
    # block garbage like "haha" or "@example.com" before it reaches the
    # mailer and fails noisily there. Uses get_attribute so both create
    # and update paths are covered.
    validate(fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :email) do
        nil -> :ok
        %Ash.CiString{} = ci -> validate_email_format(to_string(ci))
        email when is_binary(email) -> validate_email_format(email)
        _ -> :ok
      end
    end)

    # SECURITY_AUDIT_REPORT MEDIUM #4: same story for phone — Twilio
    # would reject a malformed number at send time, but by then we've
    # persisted it and enqueued a failing worker. Pre-reject here.
    # Permissive: accepts E.164 (+15125551234), US with dashes
    # (512-555-1234), US with parens ((512) 555-1234). Rejects letters
    # and numbers shorter than 10 digits.
    validate(fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :phone) do
        nil -> :ok
        "" -> :ok
        phone when is_binary(phone) -> validate_phone_format(phone)
        _ -> :ok
      end
    end)
  end

  # --- Private validation helpers ---

  defp validate_email_format(email) do
    # Local-part@domain.tld-ish. Rejects whitespace and requires a dot
    # somewhere after the @. Not a full RFC 5321 check by design.
    if String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) do
      :ok
    else
      {:error, field: :email, message: "must be a valid email address"}
    end
  end

  defp validate_phone_format(phone) do
    digits = phone |> String.graphemes() |> Enum.filter(&(&1 =~ ~r/[0-9]/)) |> length()

    cond do
      # Letters anywhere? Reject — Twilio-compatible formats are digits
      # with optional +, spaces, dashes, dots, parens.
      String.match?(phone, ~r/[A-Za-z]/) ->
        {:error, field: :phone, message: "must be a valid phone number"}

      digits < 10 ->
        {:error, field: :phone, message: "must contain at least 10 digits"}

      true ->
        :ok
    end
  end

  actions do
    defaults([:read, update: :*])

    create :create_guest do
      @doc "Creates a lightweight guest customer — no password required"
      accept([
        :email,
        :name,
        :phone,
        :utm_source,
        :utm_medium,
        :utm_campaign,
        :utm_content,
        :referrer,
        :acquired_channel_id
      ])

      change(set_attribute(:role, :guest))
    end

    read :by_email do
      argument(:email, :ci_string, allow_nil?: false)
      filter(expr(email == ^arg(:email)))
    end

    read :by_referral_code do
      argument(:referral_code, :string, allow_nil?: false)
      filter(expr(referral_code == ^arg(:referral_code)))
    end

    # One-shot email verification. Takes the token the customer clicked
    # in the signup email, validates it against the current record's
    # email + subject, and stamps email_verified_at.
    #
    # Idempotent — running again on a verified account re-stamps the
    # timestamp; no harm done. Rejects:
    #   * expired tokens (24h lifetime)
    #   * tokens issued for a different subject
    #   * tokens minted against a previous email address (so users who
    #     change their email before clicking an outstanding link need
    #     a fresh one)
    update :verify_email do
      require_atomic?(false)
      argument(:token, :string, allow_nil?: false)

      validate(fn changeset, _context ->
        customer = changeset.data
        token = Ash.Changeset.get_argument(changeset, :token)

        case MobileCarWash.Accounts.EmailVerification.verify_token(customer, token) do
          :ok -> :ok
          {:error, reason} -> {:error, field: :token, message: "verification failed: #{reason}"}
        end
      end)

      change(set_attribute(:email_verified_at, &DateTime.utc_now/0))
    end
  end

  changes do
    change(
      fn changeset, _context ->
        if changeset.action.type == :create &&
             !Ash.Changeset.get_attribute(changeset, :referral_code) do
          Ash.Changeset.force_change_attribute(
            changeset,
            :referral_code,
            generate_referral_code()
          )
        else
          changeset
        end
      end,
      on: [:create]
    )

    # Derive acquired_channel_id from the strongest signal present on
    # the changeset. Precedence: explicit value > referral > paid-UTM >
    # organic-UTM > unknown. Runs as a before_action so referred_by_id
    # set via force_change_attribute after for_create is still visible.
    change(
      fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn cs ->
          if is_nil(Ash.Changeset.get_attribute(cs, :acquired_channel_id)) do
            slug = derive_channel_slug(cs)

            case resolve_channel_id(slug) do
              nil -> cs
              id -> Ash.Changeset.force_change_attribute(cs, :acquired_channel_id, id)
            end
          else
            cs
          end
        end)
      end,
      on: [:create]
    )

    # Enqueue the verification email after a successful password signup.
    # Scoped to action.name == :register_with_password so :create_guest
    # and admin-driven creates don't trigger it. Fires on any path that
    # leads through the AshAuthentication password strategy — web
    # /auth/ routes and the API /api/v1/auth/register controller both.
    change(
      fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn cs, customer ->
          if cs.action && cs.action.name == :register_with_password do
            %{customer_id: customer.id}
            |> MobileCarWash.Notifications.VerificationEmailWorker.new(queue: :notifications)
            |> Oban.insert()
          end

          {:ok, customer}
        end)
      end,
      on: [:create]
    )
  end

  defp generate_referral_code do
    :crypto.strong_rand_bytes(5)
    |> Base.encode32(padding: false)
    |> String.slice(0, 8)
  end

  defp derive_channel_slug(changeset) do
    cond do
      Ash.Changeset.get_attribute(changeset, :referred_by_id) ->
        "referral"

      true ->
        source = changeset |> Ash.Changeset.get_attribute(:utm_source) |> norm()
        medium = changeset |> Ash.Changeset.get_attribute(:utm_medium) |> norm()
        derive_channel_from_utms(source, medium)
    end
  end

  defp norm(nil), do: nil
  defp norm(s) when is_binary(s), do: s |> String.downcase() |> String.trim()

  # Paid media mediums that Google Analytics + ad platforms use.
  @paid_mediums ~w(cpc ppc paid paid_social paidsocial paid-search paid_search display banner)
  @organic_mediums ~w(organic search seo)

  defp derive_channel_from_utms(source, medium) when medium in @paid_mediums do
    case source do
      "meta" -> "meta_paid"
      "facebook" -> "meta_paid"
      "instagram" -> "meta_paid"
      "fb" -> "meta_paid"
      "ig" -> "meta_paid"
      "google" -> "google_paid"
      "nextdoor" -> "nextdoor"
      _ -> "unknown"
    end
  end

  defp derive_channel_from_utms(_source, medium) when medium in @organic_mediums,
    do: "google_organic"

  defp derive_channel_from_utms(_, _), do: "unknown"

  defp resolve_channel_id(slug) do
    case MobileCarWash.Marketing.AcquisitionChannel
         |> Ash.Query.for_read(:by_slug, %{slug: slug})
         |> Ash.read(authorize?: false) do
      {:ok, [chan | _]} -> chan.id
      _ -> nil
    end
  end
end
