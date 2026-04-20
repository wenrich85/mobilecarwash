defmodule MobileCarWash.Marketing.Post do
  @moduledoc """
  Marketing Phase 3A: a composed social-media post, adapter-agnostic.

  Fan-out model: one Post row targets N `channels` (meta, x, tiktok, …)
  and publishes to each via the configured SocialAdapter. External
  post IDs from each platform are stashed in the `external_ids` map
  so we can later track per-platform performance.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("marketing_posts")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :body, :string do
      public?(true)
      default("")
    end

    attribute(:image_url, :string, public?: true)

    attribute :channels, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
      description("Platform slugs: meta, x, tiktok, linkedin, buffer, log")
    end

    attribute :persona_ids, {:array, :uuid} do
      default([])
      public?(true)
      description("Personas this post targets. Adapter uses this to pick an audience.")
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:draft)
      public?(true)
      constraints(one_of: [:draft, :scheduled, :published, :failed])
    end

    attribute(:scheduled_at, :utc_datetime_usec, public?: true)
    attribute(:published_at, :utc_datetime_usec, public?: true)

    attribute :external_ids, :map do
      default(%{})
      public?(true)
      description("Platform slug → remote post id, e.g. %{\"meta\" => \"fb_123\"}")
    end

    attribute(:error_message, :string, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  validations do
    validate(fn changeset, _ ->
      if changeset.action && changeset.action.type == :create do
        case Ash.Changeset.get_attribute(changeset, :channels) do
          list when is_list(list) and list != [] -> :ok
          _ -> {:error, field: :channels, message: "must include at least one channel"}
        end
      else
        :ok
      end
    end)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :body, :image_url, :channels, :persona_ids])
    end

    update :update do
      accept([:title, :body, :image_url, :channels, :persona_ids])
    end

    update :schedule do
      require_atomic?(false)
      accept([:scheduled_at])
      change(set_attribute(:status, :scheduled))
    end

    update :mark_published do
      require_atomic?(false)
      argument(:external_ids, :map, default: %{})

      change(fn changeset, _ ->
        new_ids = Ash.Changeset.get_argument(changeset, :external_ids) || %{}
        existing = Ash.Changeset.get_data(changeset, :external_ids) || %{}
        merged = Map.merge(existing, new_ids)

        changeset
        |> Ash.Changeset.force_change_attribute(:external_ids, merged)
        |> Ash.Changeset.force_change_attribute(:status, :published)
        |> Ash.Changeset.force_change_attribute(:published_at, DateTime.utc_now())
      end)
    end

    update :mark_failed do
      require_atomic?(false)
      accept([:error_message])
      change(set_attribute(:status, :failed))
    end

    read :drafts do
      filter(expr(status == :draft))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :scheduled do
      filter(expr(status == :scheduled))
      prepare(build(sort: [scheduled_at: :asc]))
    end

    read :recent do
      prepare(build(sort: [inserted_at: :desc], limit: 50))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(expr(^actor(:role) == :admin))
    end
  end
end
