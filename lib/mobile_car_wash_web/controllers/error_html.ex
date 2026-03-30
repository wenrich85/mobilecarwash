defmodule MobileCarWashWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use MobileCarWashWeb, :html

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib/mobile_car_wash_web/controllers/error_html/404.html.heex
  #   * lib/mobile_car_wash_web/controllers/error_html/500.html.heex
  #
  # embed_templates "error_html/*"

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render("404.html", _assigns) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <title>Page Not Found · Driveway Detail Co</title>
      <style>
        body { font-family: system-ui, -apple-system, sans-serif; margin: 0; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; background: #F8F9FA; color: #1E2A38; }
        h1 { font-size: 4rem; margin: 0; color: #3A7CA5; }
        p { color: #536C8B; margin: 0.5rem 0; }
        .links { margin-top: 2rem; display: flex; gap: 1rem; }
        a { display: inline-block; padding: 0.6rem 1.5rem; border-radius: 0.5rem; text-decoration: none; font-weight: 600; }
        .primary { background: #3A7CA5; color: white; }
        .ghost { border: 1px solid #CED4DA; color: #536C8B; }
      </style>
    </head>
    <body>
      <h1>404</h1>
      <p>The page you're looking for doesn't exist.</p>
      <div class="links">
        <a href="/" class="primary">Back to Home</a>
        <a href="/book" class="ghost">Book a Wash</a>
      </div>
    </body>
    </html>
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
