defmodule MobileCarWash.Operations.TechInvites do
  @moduledoc """
  Orchestrates admin-created technician setup invites.
  """

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Notifications.TechInviteEmailWorker
  alias MobileCarWash.Operations.{TechApplication, TechInvite, Technician}
  alias MobileCarWash.Repo

  require Ash.Query

  @invite_lifetime_days 7

  def create_admin_invite(attrs, opts \\ []) when is_map(attrs) do
    email = attrs |> value(:email) |> normalize_email()

    with :ok <- ensure_email_available(email) do
      result =
        transact(fn ->
          with {:ok, customer} <- create_customer(attrs, email),
               {:ok, application} <- create_application(attrs, customer),
               {:ok, technician} <- create_technician(attrs, customer),
               {raw_token, token_hash} <- generate_token_pair(),
               {:ok, invite} <- create_invite(customer, technician, token_hash, opts) do
            {:ok,
             %{
               customer: customer,
               application: application,
               technician: technician,
               invite: invite,
               raw_token: raw_token,
               invite_url: invite_url(raw_token)
             }}
          end
        end)

      case result do
        {:ok, invite_result} ->
          enqueue_invite_email(invite_result)
          {:ok, invite_result}

        {:error, _reason} = error ->
          error
      end
    end
  end

  def accept_invite(token, password, password_confirmation)
      when is_binary(token) and is_binary(password) do
    transact(fn ->
      with {:ok, invite} <- invite_for_token(token),
           :ok <- ensure_pending(invite),
           :ok <- ensure_not_expired(invite),
           {:ok, customer} <- Ash.get(Customer, invite.customer_id, authorize?: false),
           {:ok, technician} <- Ash.get(Technician, invite.technician_id, authorize?: false),
           {:ok, customer} <- set_password(customer, password, password_confirmation),
           {:ok, technician} <- activate_technician(technician),
           {:ok, invite} <- mark_accepted(invite) do
        {:ok, %{customer: customer, technician: technician, invite: invite}}
      end
    end)
  end

  def accept_invite(_token, _password, _password_confirmation), do: {:error, :invalid_token}

  def invite_url(token) do
    base =
      Application.get_env(
        :mobile_car_wash,
        :external_base_url,
        "https://drivewaydetailcosa.com"
      )

    base <> "/tech/invite/" <> URI.encode(token)
  end

  defp ensure_email_available(nil), do: {:error, :email_required}

  defp ensure_email_available(email) do
    case Customer
         |> Ash.Query.for_read(:by_email, %{email: email})
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, _customer} -> {:error, :email_taken}
      {:error, error} -> {:error, error}
    end
  end

  defp create_customer(attrs, email) do
    Customer
    |> Ash.Changeset.for_create(:create_technician_invitee, %{
      email: email,
      name: value(attrs, :name) || value(attrs, :preferred_name),
      phone: value(attrs, :phone)
    })
    |> ash_create()
  end

  defp create_application(attrs, customer) do
    TechApplication
    |> Ash.Changeset.for_create(:create_admin_invite, application_attrs(attrs))
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> ash_create()
  end

  defp create_technician(attrs, customer) do
    Technician
    |> Ash.Changeset.for_create(:create, %{
      name: value(attrs, :name) || value(attrs, :preferred_name),
      phone: value(attrs, :phone),
      active: false,
      zone: value(attrs, :assigned_zone) || value(attrs, :preferred_zone),
      pay_rate_cents: value(attrs, :accepted_pay_rate_cents) || 2500,
      pay_rate_pct: value(attrs, :accepted_pay_rate_pct),
      van_id: value(attrs, :van_id)
    })
    |> Ash.Changeset.force_change_attribute(:user_account_id, customer.id)
    |> ash_create()
  end

  defp create_invite(customer, technician, token_hash, opts) do
    TechInvite
    |> Ash.Changeset.for_create(:create, %{
      customer_id: customer.id,
      technician_id: technician.id,
      token_hash: token_hash,
      expires_at: Keyword.get(opts, :expires_at, default_expires_at())
    })
    |> ash_create()
  end

  defp enqueue_invite_email(%{customer: customer, invite: invite, invite_url: invite_url}) do
    %{
      customer_id: customer.id,
      invite_url: invite_url,
      expires_at: DateTime.to_iso8601(invite.expires_at)
    }
    |> TechInviteEmailWorker.new(queue: :notifications)
    |> Oban.insert()
  end

  defp invite_for_token(token) do
    TechInvite
    |> Ash.Query.filter(token_hash == ^hash_token(token))
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :invalid_token}
      {:ok, invite} -> {:ok, invite}
      {:error, error} -> {:error, error}
    end
  end

  defp ensure_pending(%{status: :pending}), do: :ok
  defp ensure_pending(_invite), do: {:error, :invite_not_pending}

  defp ensure_not_expired(invite) do
    if DateTime.compare(invite.expires_at, DateTime.utc_now()) == :lt do
      invite
      |> Ash.Changeset.for_update(:update, %{status: :expired})
      |> ash_update()

      {:error, :invite_expired}
    else
      :ok
    end
  end

  defp set_password(customer, password, password_confirmation) do
    customer
    |> Ash.Changeset.for_update(:set_invite_password, %{
      password: password,
      password_confirmation: password_confirmation
    })
    |> ash_update()
  end

  defp activate_technician(technician) do
    technician
    |> Ash.Changeset.for_update(:update, %{active: true})
    |> ash_update()
  end

  defp mark_accepted(invite) do
    invite
    |> Ash.Changeset.for_update(:update, %{status: :accepted, accepted_at: DateTime.utc_now()})
    |> ash_update()
  end

  defp application_attrs(attrs) do
    %{
      preferred_name: value(attrs, :preferred_name) || value(attrs, :name),
      phone: value(attrs, :phone),
      home_zip: value(attrs, :home_zip),
      preferred_zone: value(attrs, :preferred_zone),
      availability_weekdays: truthy?(value(attrs, :availability_weekdays)),
      availability_weekends: truthy?(value(attrs, :availability_weekends)),
      availability_mornings: truthy?(value(attrs, :availability_mornings)),
      availability_afternoons: truthy?(value(attrs, :availability_afternoons)),
      availability_evenings: truthy?(value(attrs, :availability_evenings)),
      experience_level: value(attrs, :experience_level) || :none,
      has_valid_driver_license: truthy?(value(attrs, :has_valid_driver_license)),
      has_reliable_transportation: truthy?(value(attrs, :has_reliable_transportation)),
      can_lift_supplies: truthy?(value(attrs, :can_lift_supplies)),
      desired_hours_per_week: value(attrs, :desired_hours_per_week),
      earliest_start_date: value(attrs, :earliest_start_date),
      emergency_contact_name: value(attrs, :emergency_contact_name),
      emergency_contact_phone: value(attrs, :emergency_contact_phone),
      why_work_with_us: value(attrs, :why_work_with_us),
      experience_notes: value(attrs, :experience_notes),
      schedule_notes: value(attrs, :schedule_notes),
      review_notes: value(attrs, :review_notes),
      decision_note: value(attrs, :decision_note),
      accepted_pay_rate_cents: value(attrs, :accepted_pay_rate_cents),
      accepted_pay_rate_pct: value(attrs, :accepted_pay_rate_pct),
      assigned_zone: value(attrs, :assigned_zone),
      van_id: value(attrs, :van_id),
      active: false
    }
  end

  defp generate_token_pair do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {raw_token, hash_token(raw_token)}
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp default_expires_at do
    DateTime.add(DateTime.utc_now(), @invite_lifetime_days, :day)
  end

  defp transact(fun) do
    Process.put(notifications_key(), [])

    result =
      Repo.transaction(fn ->
        case fun.() do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    notifications = Process.delete(notifications_key()) || []

    case result do
      {:ok, result} ->
        Ash.Notifier.notify(notifications)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ash_create(changeset) do
    case Ash.create(changeset, authorize?: false, return_notifications?: true) do
      {:ok, record, notifications} ->
        record_notifications(notifications)
        {:ok, record}

      {:error, error} ->
        {:error, error}
    end
  end

  defp ash_update(changeset) do
    case Ash.update(changeset, authorize?: false, return_notifications?: true) do
      {:ok, record, notifications} ->
        record_notifications(notifications)
        {:ok, record}

      {:error, error} ->
        {:error, error}
    end
  end

  defp record_notifications(notifications) do
    Process.put(notifications_key(), Process.get(notifications_key(), []) ++ notifications)
  end

  defp notifications_key, do: {__MODULE__, :notifications}

  defp value(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp normalize_email(nil), do: nil
  defp normalize_email(email), do: email |> to_string() |> String.trim() |> String.downcase()

  defp truthy?(value) when value in [true, "true", "1", 1, "on"], do: true
  defp truthy?(_value), do: false
end
