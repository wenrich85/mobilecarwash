defmodule MobileCarWash.Notifications do
  @moduledoc """
  The Notifications domain — customer-facing delivery via push (APNs / FCM),
  SMS, and email. Owns the `DeviceToken` resource that the APNs push pipeline
  queries to find the set of devices each customer has opted in.
  """
  use Ash.Domain

  resources do
    resource MobileCarWash.Notifications.DeviceToken
  end
end
