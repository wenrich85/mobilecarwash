defmodule MobileCarWash.Operations.ShopConfig do
  @moduledoc """
  Central access to physical operating parameters: shop origin coordinates,
  travel speed assumptions, and routing defaults. All values are overridable
  through application config.
  """

  @default_origin {29.65, -98.42}

  @doc "Shop origin coordinates as `{latitude, longitude}`. Defaults to 5010 Foot Wedge, San Antonio TX 78261."
  def origin do
    Application.get_env(:mobile_car_wash, :shop_origin, @default_origin)
  end
end
