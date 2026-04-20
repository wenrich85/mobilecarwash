defmodule MobileCarWashWeb.Admin.CampaignsLiveTest do
  @moduledoc """
  Marketing Phase 3A / Slice 4: /admin/campaigns is the social-media
  composer. List existing posts + new-post form + publish button.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.Post

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "camp-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Camp Admin",
        phone: "+15125557400"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, customer) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(customer.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  describe "auth guard" do
    test "anonymous redirects to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/campaigns")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "draft + publish flow" do
    test "creates a draft and publishes it via the log adapter",
         %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, lv, _html} = live(conn, ~p"/admin/campaigns")

      lv
      |> form("#post-form", %{
        "post" => %{
          "title" => "Spring detail special",
          "body" => "Book now — 20% off through April",
          "channels" => ["log", "meta"]
        }
      })
      |> render_submit()

      [post] = Post |> Ash.read!(authorize?: false)
      assert post.title == "Spring detail special"

      # Click publish on the newly created row
      lv |> element("##{"publish-#{post.id}"}") |> render_click()

      {:ok, published} = Ash.get(Post, post.id, authorize?: false)
      assert published.status == :published
      assert Map.has_key?(published.external_ids, "log")
    end
  end

  describe "channel selection" do
    test "submitting with no channels surfaces an error", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, lv, _html} = live(conn, ~p"/admin/campaigns")

      html =
        lv
        |> form("#post-form", %{
          "post" => %{
            "title" => "Empty channels",
            "body" => "",
            "channels" => []
          }
        })
        |> render_submit()

      assert html =~ "channel"
    end
  end

  describe "list view" do
    test "shows recent posts with their status badges", %{conn: conn} do
      admin = register_admin!()

      {:ok, _} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Existing draft",
          body: "",
          channels: ["log"]
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/campaigns")

      assert html =~ "Existing draft"
      assert html =~ "draft"
    end
  end
end
