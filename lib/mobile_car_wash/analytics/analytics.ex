defmodule MobileCarWash.Analytics do
  @moduledoc """
  The Analytics domain — event tracking, experiments, and validated learning.
  This is the Build→Measure→Learn engine that drives pivot/persevere decisions.
  """
  use Ash.Domain

  require Ash.Query

  alias MobileCarWash.Analytics.CookieConsent

  resources do
    resource MobileCarWash.Analytics.Event
    resource MobileCarWash.Analytics.Experiment
    resource MobileCarWash.Analytics.ExperimentAssignment
    resource CookieConsent
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
end
