defmodule MobileCarWashWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.Components

  override Components.Banner do
    set :image_url, "/images/logo_light.svg"
    set :dark_image_url, "/images/logo_dark.svg"
    set :image_class, "h-12 block dark:hidden"
    set :dark_image_class, "h-12 hidden dark:block"
    set :root_class, "w-full flex justify-center py-4"
  end

  override Components.SignIn do
    set :root_class, "mx-auto w-full max-w-md px-4"
    set :strategy_class, "mx-auto w-full max-w-sm"
  end

  override AshAuthentication.Phoenix.SignInLive do
    set :root_class, "min-h-screen flex items-center justify-center bg-base-200"
  end

  override Components.Password do
    set :root_class, nil
    set :label_class, "text-2xl font-bold text-base-content mb-4"
    set :form_class, "space-y-4"
    set :spacer_class, "py-1"
    set :slot_class, "text-center text-sm text-base-content/80 mt-4"
  end

  override Components.Password.Input do
    set :root_class, "form-control"
    set :label_class, "label label-text font-medium"
    set :input_class, "input input-bordered w-full"
    set :input_class_with_error, "input input-bordered input-error w-full"
    set :submit_class, "btn btn-primary btn-block mt-4"
    set :error_ul, "text-error text-xs mt-1"
    set :error_li, nil
  end
end
