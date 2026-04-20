defmodule MobileCarWash.Analytics do
  @moduledoc """
  The Analytics domain — event tracking, experiments, and validated learning.
  This is the Build→Measure→Learn engine that drives pivot/persevere decisions.
  """
  use Ash.Domain

  require Ash.Query

  alias MobileCarWash.Analytics.{CookieConsent, Event, UserAgent}

  resources do
    resource(MobileCarWash.Analytics.Event)
    resource(MobileCarWash.Analytics.Experiment)
    resource(MobileCarWash.Analytics.ExperimentAssignment)
    resource(CookieConsent)
  end

  @doc """
  Returns the most recent CookieConsent row for the given session_id,
  or nil if none recorded.
  """
  @spec consent_for_session(String.t()) :: CookieConsent.t() | nil
  def consent_for_session(session_id) when is_binary(session_id) do
    case CookieConsent
         |> Ash.Query.for_read(:for_session, %{session_id: session_id})
         |> Ash.Query.limit(1)
         |> Ash.read(authorize?: false) do
      {:ok, [row | _]} -> row
      _ -> nil
    end
  end

  def consent_for_session(_), do: nil

  @doc """
  Does this session consent to the given category?

  Essential is always true — it's required for the app to function
  and covers cookies like session/auth/CSRF. Analytics and marketing
  require an explicit CookieConsent row with the category set to true.
  """
  @spec consents?(String.t(), :essential | :analytics | :marketing) :: boolean()
  def consents?(_session_id, :essential), do: true

  def consents?(session_id, category) when category in [:analytics, :marketing] do
    case consent_for_session(session_id) do
      nil -> false
      consent -> Map.get(consent, category, false)
    end
  end

  @doc """
  Consent-gated event track. Takes a map with keys:

    * :session_id      (required)
    * :event_name      (required)
    * :category        — :essential | :analytics | :marketing (default :analytics)
    * :source          — defaults "web"
    * :properties      — defaults %{}
    * :customer_id     — optional
    * :user_agent      — optional; auto-parsed into device_type/os/browser
                         when the explicit fields aren't provided
    * :device_type / :os / :browser — override the UA parse
    * :page_path       — optional

  Returns `:ok` when the event is written, `:dropped_no_consent` when
  the session hasn't granted the relevant category. Essential events
  always fire.
  """
  @spec track_event(map()) :: :ok | :dropped_no_consent | {:error, term()}
  def track_event(%{session_id: session_id, event_name: _} = args) do
    category = Map.get(args, :category, :analytics)

    if consents?(session_id, category) do
      write_event(args)
    else
      :dropped_no_consent
    end
  end

  defp write_event(args) do
    parsed =
      case args[:user_agent] do
        ua when is_binary(ua) and ua != "" -> UserAgent.parse(ua)
        _ -> %{device_type: :unknown, os: nil, browser: nil}
      end

    attrs = %{
      session_id: args.session_id,
      event_name: args.event_name,
      source: Map.get(args, :source, "web"),
      properties: Map.get(args, :properties, %{}),
      customer_id: args[:customer_id],
      device_type: args[:device_type] || parsed.device_type,
      os: args[:os] || parsed.os,
      browser: args[:browser] || parsed.browser,
      user_agent: args[:user_agent],
      page_path: args[:page_path]
    }

    case Event
         |> Ash.Changeset.for_create(:track, attrs)
         |> Ash.create(authorize?: false) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
