defmodule MobileCarWash.Billing do
  @moduledoc """
  The Billing domain — subscription plans, subscriptions, usage tracking, and payments.
  """
  use Ash.Domain

  resources do
    resource(MobileCarWash.Billing.SubscriptionPlan)
    resource(MobileCarWash.Billing.Subscription)
    resource(MobileCarWash.Billing.SubscriptionUsage)
    resource(MobileCarWash.Billing.Payment)
  end
end
