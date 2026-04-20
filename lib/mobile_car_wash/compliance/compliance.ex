defmodule MobileCarWash.Compliance do
  @moduledoc """
  The Compliance domain — business formation tracking, government filings,
  veteran certifications, and recurring compliance tasks.
  """
  use Ash.Domain

  resources do
    resource(MobileCarWash.Compliance.TaskCategory)
    resource(MobileCarWash.Compliance.FormationTask)
  end
end
