defmodule MobileCarWashWeb.SecurityHeadersS3Test do
  @moduledoc """
  Direct-to-Spaces uploads (the S3PUT uploader) XHR straight from the
  browser to the bucket endpoint, so CSP connect-src must allow the
  configured S3 host — without it every presigned PUT is blocked by the
  browser before it is sent (upload fails with :external_client_failure
  while curl against the same URL succeeds).
  """
  # Mutates :ex_aws app env — must not run concurrently with other tests.
  use MobileCarWashWeb.ConnCase, async: false

  describe "with an S3 endpoint configured (prod shape)" do
    setup do
      previous = Application.get_env(:ex_aws, :s3)

      Application.put_env(:ex_aws, :s3, %{
        scheme: "https://",
        host: "sfo3.digitaloceanspaces.com",
        region: "sfo3"
      })

      on_exit(fn ->
        case previous do
          nil -> Application.delete_env(:ex_aws, :s3)
          val -> Application.put_env(:ex_aws, :s3, val)
        end
      end)

      :ok
    end

    test "CSP connect-src allows the object-storage endpoint", %{conn: conn} do
      conn = get(conn, "/")

      csp = get_resp_header(conn, "content-security-policy") |> List.first()
      assert csp, "expected CSP header on public route"

      [connect_src] =
        csp
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "connect-src"))

      assert connect_src =~ "https://sfo3.digitaloceanspaces.com",
             "presigned PUTs XHR to the bucket endpoint; connect-src must allow it"
    end
  end

  describe "without an S3 endpoint configured (dev/test shape)" do
    test "connect-src carries no storage host", %{conn: conn} do
      conn = get(conn, "/")
      csp = get_resp_header(conn, "content-security-policy") |> List.first()

      refute csp =~ "digitaloceanspaces",
             "no S3 endpoint configured, so none should appear in the CSP"
    end
  end
end
