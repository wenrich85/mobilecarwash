defmodule MobileCarWashWeb.Api.V1.AdminCustomersController do
  @moduledoc """
  Admin-facing customer rows for native command center clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Accounts.{Customer, CustomerNote}

  alias MobileCarWash.Marketing.{
    AcquisitionChannel,
    CustomerTag,
    Persona,
    PersonaMembership,
    Personas,
    Tag
  }

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Reporting.CustomerList

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  @page_size 50

  def index(conn, params) do
    filters = %{
      q: params["q"],
      channel_id: params["channel"],
      role: params["role"],
      verified: params["verified"],
      tag_id: params["tag"]
    }

    customers =
      filters
      |> CustomerList.list_filtered()
      |> CustomerList.sort(params["sort"] || "joined_desc")
      |> Enum.take(@page_size)

    channels = load_channels(customers)
    tag_map = load_tags(customers)
    tag_reasons = load_tag_reasons(customers)

    data =
      Enum.map(customers, fn customer ->
        customer_json(customer, channels, tag_map, tag_reasons)
      end)

    json(conn, %{data: data})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    else
      _ -> not_found(conn)
    end
  end

  def disable(conn, %{"id" => id, "reason" => reason}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false),
         {:ok, customer} <-
           customer
           |> Ash.Changeset.for_update(:disable, %{reason: reason})
           |> Ash.update(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    end
  end

  def reenable(conn, %{"id" => id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false),
         {:ok, customer} <-
           customer
           |> Ash.Changeset.for_update(:reenable, %{})
           |> Ash.update(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    end
  end

  def credit(conn, %{"id" => id, "amount_cents" => amount_cents}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false),
         {:ok, customer} <-
           customer
           |> Ash.Changeset.for_update(:update, %{})
           |> Ash.Changeset.force_change_attribute(
             :referral_credit_cents,
             (customer.referral_credit_cents || 0) + parse_int(amount_cents)
           )
           |> Ash.update(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    end
  end

  def add_note(conn, %{"id" => id, "body" => body} = params) do
    pinned = params["pinned"] in [true, "true"]

    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false),
         {:ok, _note} <-
           CustomerNote
           |> Ash.Changeset.for_create(:add, %{
             customer_id: customer.id,
             author_id: current_user(conn).id,
             body: body,
             pinned: pinned
           })
           |> Ash.create(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    end
  end

  def toggle_note(conn, %{"customer_id" => customer_id, "note_id" => note_id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, customer_id, authorize?: false),
         {:ok, %CustomerNote{} = note} <- Ash.get(CustomerNote, note_id, authorize?: false),
         true <- note.customer_id == customer.id,
         {:ok, _note} <-
           note
           |> Ash.Changeset.for_update(:toggle_pin, %{})
           |> Ash.update(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    else
      false -> not_found(conn)
      _ -> not_found(conn)
    end
  end

  def delete_note(conn, %{"customer_id" => customer_id, "note_id" => note_id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, customer_id, authorize?: false),
         {:ok, %CustomerNote{} = note} <- Ash.get(CustomerNote, note_id, authorize?: false),
         true <- note.customer_id == customer.id,
         :ok <- Ash.destroy(note, authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    else
      false -> not_found(conn)
      _ -> not_found(conn)
    end
  end

  def tag(conn, %{"id" => id, "tag_id" => tag_id} = params) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false),
         {:ok, _tag} <-
           CustomerTag
           |> Ash.Changeset.for_create(:tag, %{
             customer_id: customer.id,
             tag_id: tag_id,
             author_id: current_user(conn).id,
             reason: blank_to_nil(params["reason"])
           })
           |> Ash.create(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    end
  end

  def untag(conn, %{"customer_id" => customer_id, "tag_id" => tag_id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, customer_id, authorize?: false),
         %CustomerTag{} = customer_tag <- find_customer_tag(customer.id, tag_id),
         :ok <- Ash.destroy(customer_tag, authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    else
      _ -> not_found(conn)
    end
  end

  def channel(conn, %{"id" => id, "channel_id" => channel_id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false),
         {:ok, customer} <-
           customer
           |> Ash.Changeset.for_update(:update, %{})
           |> Ash.Changeset.force_change_attribute(:acquired_channel_id, blank_to_nil(channel_id))
           |> Ash.update(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    end
  end

  def resend_verification(conn, %{"id" => id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false) do
      if is_nil(customer.email_verified_at) do
        %{"customer_id" => customer.id}
        |> MobileCarWash.Notifications.VerificationEmailWorker.new()
        |> Oban.insert!()
      end

      json(conn, %{data: detail_json(customer)})
    else
      _ -> not_found(conn)
    end
  end

  def assign_persona(conn, %{"id" => id, "persona_id" => persona_id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false),
         {:ok, _membership} <-
           PersonaMembership
           |> Ash.Changeset.for_create(:assign, %{
             customer_id: customer.id,
             persona_id: persona_id,
             manually_assigned: true
           })
           |> Ash.create(authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    end
  end

  def remove_persona(conn, %{"customer_id" => customer_id, "membership_id" => membership_id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, customer_id, authorize?: false),
         {:ok, %PersonaMembership{} = membership} <-
           Ash.get(PersonaMembership, membership_id, authorize?: false),
         true <- membership.customer_id == customer.id,
         :ok <- Ash.destroy(membership, authorize?: false) do
      json(conn, %{data: detail_json(customer)})
    else
      false -> not_found(conn)
      _ -> not_found(conn)
    end
  end

  def recompute_personas(conn, %{"id" => id}) do
    with {:ok, %Customer{} = customer} <- Ash.get(Customer, id, authorize?: false) do
      :ok = Personas.assign_matching!(customer)
      json(conn, %{data: detail_json(customer)})
    else
      _ -> not_found(conn)
    end
  end

  defp require_admin(conn, _opts) do
    case current_user(conn) do
      %{role: :admin} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden", message: "Admin role required"})
        |> halt()
    end
  end

  defp load_channels(customers) do
    ids =
      customers
      |> Enum.map(& &1.acquired_channel_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    load_map(AcquisitionChannel, ids)
  end

  defp load_tags(customers) do
    ids =
      customers
      |> Enum.flat_map(& &1.__tag_ids__)
      |> Enum.uniq()

    load_map(Tag, ids)
  end

  defp load_tag_reasons(customers) do
    customer_ids = customers |> Enum.map(& &1.id) |> Enum.uniq()
    tag_ids = customers |> Enum.flat_map(& &1.__tag_ids__) |> Enum.uniq()

    case {customer_ids, tag_ids} do
      {[], _} ->
        %{}

      {_, []} ->
        %{}

      _ ->
        CustomerTag
        |> Ash.Query.filter(customer_id in ^customer_ids and tag_id in ^tag_ids)
        |> Ash.read!(authorize?: false)
        |> Map.new(&{{&1.customer_id, &1.tag_id}, &1.reason})
    end
  end

  defp load_map(_resource, []), do: %{}

  defp load_map(resource, ids) do
    resource
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1})
  end

  defp customer_json(customer, channels, tag_map, tag_reasons) do
    channel = Map.get(channels, customer.acquired_channel_id)

    %{
      id: customer.id,
      email: to_string(customer.email),
      name: customer.name,
      phone: customer.phone,
      role: to_string(customer.role),
      verified: not is_nil(customer.email_verified_at),
      disabled: not is_nil(customer.disabled_at),
      acquired_channel_id: customer.acquired_channel_id,
      acquired_channel_name: channel && channel.display_name,
      inserted_at: customer.inserted_at,
      lifetime_revenue_cents: customer.__lifetime_revenue__ || 0,
      last_wash_at: customer.__last_wash_at__,
      tags: tags_json(customer, tag_map, tag_reasons)
    }
  end

  defp detail_json(customer) do
    channel = load_one(AcquisitionChannel, customer.acquired_channel_id)
    notes = notes_for(customer.id)
    customer_tags = customer_tags_for(customer.id)
    tag_map = load_map(Tag, Enum.map(customer_tags, & &1.tag_id))
    memberships = memberships_for(customer.id)
    persona_map = load_map(Persona, Enum.map(memberships, & &1.persona_id))

    customer
    |> customer_base_json(channel)
    |> Map.merge(%{
      disabled_reason: customer.disabled_reason,
      referral_credit_cents: customer.referral_credit_cents || 0,
      note_count: length(notes),
      notes: Enum.map(notes, &note_json/1),
      tags: Enum.map(customer_tags, &customer_tag_json(&1, tag_map)),
      available_tags: available_tags_json(),
      personas: Enum.flat_map(memberships, &persona_membership_json(&1, persona_map)),
      available_personas: available_personas_json(),
      available_channels: available_channels_json(),
      recent_appointments: recent_appointments_json(customer.id)
    })
  end

  defp customer_base_json(customer, channel) do
    %{
      id: customer.id,
      email: to_string(customer.email),
      name: customer.name,
      phone: customer.phone,
      role: to_string(customer.role),
      verified: not is_nil(customer.email_verified_at),
      disabled: not is_nil(customer.disabled_at),
      acquired_channel_id: customer.acquired_channel_id,
      acquired_channel_name: channel && channel.display_name,
      inserted_at: customer.inserted_at,
      lifetime_revenue_cents: 0,
      last_wash_at: nil
    }
  end

  defp notes_for(customer_id) do
    CustomerNote
    |> Ash.Query.filter(customer_id == ^customer_id)
    |> Ash.Query.sort(pinned: :desc, inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp customer_tags_for(customer_id) do
    CustomerTag
    |> Ash.Query.filter(customer_id == ^customer_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp memberships_for(customer_id) do
    PersonaMembership
    |> Ash.Query.filter(customer_id == ^customer_id)
    |> Ash.read!(authorize?: false)
  end

  defp recent_appointments_json(customer_id) do
    appointments =
      Appointment
      |> Ash.Query.filter(customer_id == ^customer_id)
      |> Ash.Query.sort(scheduled_at: :desc)
      |> Ash.Query.limit(5)
      |> Ash.read!(authorize?: false)

    service_map =
      appointments
      |> Enum.map(& &1.service_type_id)
      |> then(&load_map(ServiceType, &1))

    Enum.map(appointments, fn appointment ->
      service = Map.get(service_map, appointment.service_type_id)

      %{
        id: appointment.id,
        status: to_string(appointment.status),
        scheduled_at: appointment.scheduled_at,
        service_type_id: appointment.service_type_id,
        service_name: service && service.name,
        price_cents: appointment.price_cents || 0
      }
    end)
  end

  defp available_tags_json do
    Tag
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn tag ->
      %{
        id: tag.id,
        name: tag.name,
        slug: tag.slug,
        color: to_string(tag.color)
      }
    end)
  end

  defp available_personas_json do
    Persona
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(sort_order: :asc, name: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn persona ->
      %{
        id: persona.id,
        name: persona.name,
        slug: persona.slug
      }
    end)
  end

  defp available_channels_json do
    AcquisitionChannel
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(sort_order: :asc, display_name: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn channel ->
      %{
        id: channel.id,
        slug: channel.slug,
        display_name: channel.display_name,
        category: to_string(channel.category)
      }
    end)
  end

  defp note_json(note) do
    %{
      id: note.id,
      body: note.body,
      pinned: note.pinned,
      inserted_at: note.inserted_at
    }
  end

  defp customer_tag_json(customer_tag, tag_map) do
    tag = Map.fetch!(tag_map, customer_tag.tag_id)

    %{
      id: tag.id,
      name: tag.name,
      slug: tag.slug,
      color: to_string(tag.color),
      reason: customer_tag.reason
    }
  end

  defp persona_membership_json(membership, persona_map) do
    case Map.get(persona_map, membership.persona_id) do
      nil ->
        []

      persona ->
        [
          %{
            id: membership.id,
            persona_id: persona.id,
            name: persona.name,
            slug: persona.slug,
            manually_assigned: membership.manually_assigned
          }
        ]
    end
  end

  defp tags_json(customer, tag_map, tag_reasons) do
    Enum.flat_map(customer.__tag_ids__, fn tag_id ->
      case Map.get(tag_map, tag_id) do
        nil ->
          []

        tag ->
          [
            %{
              id: tag.id,
              name: tag.name,
              slug: tag.slug,
              color: to_string(tag.color),
              reason: Map.get(tag_reasons, {customer.id, tag.id})
            }
          ]
      end
    end)
  end

  defp find_customer_tag(customer_id, tag_id) do
    CustomerTag
    |> Ash.Query.filter(customer_id == ^customer_id and tag_id == ^tag_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp load_one(_resource, nil), do: nil

  defp load_one(resource, id) do
    case Ash.get(resource, id, authorize?: false) do
      {:ok, item} -> item
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_int(_value), do: 0

  defp blank_to_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
