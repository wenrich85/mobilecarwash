defmodule MobileCarWash.Notifications.Email.Layout do
  @moduledoc """
  Shared HTML and text layout helpers for transactional emails.

  All transactional emails use `wrap_html/1` (HTML body) and `wrap_text/1`
  (text body) to get a consistent header (logo) and footer (legal). Inline
  SVG logo avoids dependency on external image fetches that hurt sender
  reputation in some clients.

  Buttons are styled inline (no `<style>` tag — many email clients strip
  them).
  """

  @doc """
  Wraps content HTML in the branded email document layout.

  Returns a complete `<!doctype html>...</html>` string.
  """
  def wrap_html(content_html) when is_binary(content_html) do
    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Driveway Detail Co</title>
    </head>
    <body style="margin:0;padding:0;background:#f1f5f9;font-family:'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:32px 16px;">
        <tr>
          <td align="center">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border-radius:12px;padding:24px;">
              <tr>
                <td style="padding-bottom:16px;border-bottom:1px solid #e2e8f0;">
                  #{header_logo_svg()}
                </td>
              </tr>
              <tr>
                <td style="padding:24px 0;color:#0f172a;font-size:14px;line-height:1.55;">
                  #{content_html}
                </td>
              </tr>
              <tr>
                <td style="padding-top:16px;border-top:1px solid #e2e8f0;text-align:center;color:#64748b;font-size:12px;">
                  <p style="margin:0 0 8px;">Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned</p>
                  <p style="margin:0;">
                    <a href="https://drivewaydetailcosa.com/privacy" style="color:#06b6d4;text-decoration:none;">Privacy</a> ·
                    <a href="https://drivewaydetailcosa.com/terms" style="color:#06b6d4;text-decoration:none;">Terms</a> ·
                    <a href="https://drivewaydetailcosa.com/unsubscribe" style="color:#06b6d4;text-decoration:none;">Unsubscribe</a>
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  @doc """
  Wraps content text with a plain-text header and footer.
  """
  def wrap_text(content_text) when is_binary(content_text) do
    """
    Driveway Detail Co
    =================

    #{content_text}

    ---
    Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned
    Privacy: https://drivewaydetailcosa.com/privacy
    Terms:   https://drivewaydetailcosa.com/terms
    Unsubscribe: https://drivewaydetailcosa.com/unsubscribe
    """
  end

  @doc """
  Renders a branded CTA button as inline-styled HTML.

  Variants:
    * `:primary` (default) — cyan background, white text
    * `:secondary` — slate background, dark text
  """
  def button(label, url, variant \\ :primary)
      when is_binary(label) and is_binary(url) and variant in [:primary, :secondary] do
    {bg, fg} =
      case variant do
        :primary -> {"#06b6d4", "#ffffff"}
        :secondary -> {"#f1f5f9", "#0f172a"}
      end

    """
    <a href="#{url}" style="display:inline-block;background:#{bg};color:#{fg};padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;font-family:'Inter',sans-serif;font-size:14px;">#{label}</a>
    """
  end

  defp header_logo_svg do
    # Inline pin+drop + wordmark.
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 40" width="180" height="30" style="display:block;">
      <path d="M16 3 C9 3 4 8 4 15 C4 22 16 35 16 35 C16 35 28 22 28 15 C28 8 23 3 16 3Z" fill="#1e293b"/>
      <path d="M16 8 C16 8 12 13 12 16 C12 18 13.7 20 16 20 C18.3 20 20 18 20 16 C20 13 16 8 16 8Z" fill="#06b6d4"/>
      <text x="44" y="25" font-family="'Inter',sans-serif" font-size="18" font-weight="600" letter-spacing="-0.4" fill="#0f172a">Driveway Detail Co</text>
    </svg>
    """
  end
end
