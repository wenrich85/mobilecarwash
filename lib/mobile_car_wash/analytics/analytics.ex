defmodule MobileCarWash.Analytics do
  @moduledoc """
  The Analytics domain — event tracking, experiments, and validated learning.
  This is the Build→Measure→Learn engine that drives pivot/persevere decisions.
  """
  use Ash.Domain

  resources do
    resource MobileCarWash.Analytics.Event
    resource MobileCarWash.Analytics.Experiment
    resource MobileCarWash.Analytics.ExperimentAssignment
  end
end
