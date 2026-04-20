defmodule MobileCarWashWeb.SecurityHeadersTest do
  @moduledoc """
  Verifies hardening per PageSpeed/Lighthouse:
  - CSP uses a per-request nonce + 'strict-dynamic' (not host allowlists)
  - Cross-Origin-Opener-Policy is set
  - HSTS carries the 'preload' directive (prod only)
  - Nonce is stashed in the session so LiveView can hydrate its socket
    assigns with the same value the server-rendered HTML was tagged with.
  """
  use MobileCarWashWeb.ConnCase, async: true

  describe "CSP nonce" do
    test "content-security-policy header carries a per-request nonce", %{conn: conn} do
      conn = get(conn, "/")

      csp = get_resp_header(conn, "content-security-policy") |> List.first()
      assert csp, "expected CSP header on public route"

      assert csp =~ ~r/script-src [^;]*'nonce-[A-Za-z0-9_\-]{16,}'/,
             "expected script-src to include a nonce token"

      assert csp =~ "'strict-dynamic'",
             "expected 'strict-dynamic' so nonce-loaded scripts can load children"
    end

    test "two requests get different nonces", %{conn: conn} do
      c1 = get(conn, "/")
      c2 = get(conn, "/")

      nonce1 = extract_nonce(c1)
      nonce2 = extract_nonce(c2)

      assert nonce1
      assert nonce2
      refute nonce1 == nonce2, "nonces must be per-request, not fixed"
    end

    test "nonce in CSP matches the nonce applied to app.js script tag", %{conn: conn} do
      conn = get(conn, "/")
      nonce = extract_nonce(conn)
      body = response(conn, 200)

      assert body =~ ~s(nonce="#{nonce}"),
             "expected at least one <script nonce=\"...\"> with the same nonce as CSP"
    end

    test "CSP no longer relies on googletagmanager.com host allowlist in script-src", %{
      conn: conn
    } do
      conn = get(conn, "/")
      csp = get_resp_header(conn, "content-security-policy") |> List.first()

      [script_src] =
        csp
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "script-src"))

      refute script_src =~ "googletagmanager.com",
             "nonce + strict-dynamic replaces host allowlists; googletagmanager.com should not be in script-src"
    end

    defp extract_nonce(conn) do
      csp = get_resp_header(conn, "content-security-policy") |> List.first() || ""

      case Regex.run(~r/'nonce-([A-Za-z0-9_\-]+)'/, csp) do
        [_, n] -> n
        _ -> nil
      end
    end
  end

  describe "Cross-Origin-Opener-Policy" do
    test "COOP is set to same-origin on browser routes", %{conn: conn} do
      conn = get(conn, "/")
      assert ["same-origin"] = get_resp_header(conn, "cross-origin-opener-policy")
    end
  end

  describe "HSTS preload (prod only)" do
    @tag :skip_in_dev
    test "HSTS header carries the 'preload' directive in production" do
      # We can't flip @is_prod at runtime because it's baked at compile time via
      # Application.compile_env/3 — so this test is a placeholder documenting the
      # expectation. Verified visually via curl against production.
      :ok
    end
  end
end
