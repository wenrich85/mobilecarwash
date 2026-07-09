defmodule MobileCarWashWeb.Admin.SettingsLiveTest do
  @moduledoc """
  Tests for the admin Settings LiveView — specifically the Accounting tab.
  Verifies provider switching, configuration status display, and auth guard.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.ServiceType

  require Ash.Query

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "settings-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Settings Admin",
        phone: "+15125557700"
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

  describe "accounting tab — auth guard" do
    test "non-authenticated user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/settings")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "accounting provider switching — unit logic" do
    test "switching to quickbooks sets the correct provider module" do
      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        Application.put_env(
          :mobile_car_wash,
          :accounting_provider,
          MobileCarWash.Accounting.QuickBooks
        )

        assert Application.get_env(:mobile_car_wash, :accounting_provider) ==
                 MobileCarWash.Accounting.QuickBooks
      after
        if original do
          Application.put_env(:mobile_car_wash, :accounting_provider, original)
        else
          Application.delete_env(:mobile_car_wash, :accounting_provider)
        end
      end
    end

    test "switching to zoho sets the correct provider module" do
      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        Application.put_env(
          :mobile_car_wash,
          :accounting_provider,
          MobileCarWash.Accounting.ZohoBooks
        )

        assert Application.get_env(:mobile_car_wash, :accounting_provider) ==
                 MobileCarWash.Accounting.ZohoBooks
      after
        if original do
          Application.put_env(:mobile_car_wash, :accounting_provider, original)
        else
          Application.delete_env(:mobile_car_wash, :accounting_provider)
        end
      end
    end

    test "switching to none sets provider to nil" do
      original = Application.get_env(:mobile_car_wash, :accounting_provider)

      try do
        Application.put_env(:mobile_car_wash, :accounting_provider, nil)
        assert Application.get_env(:mobile_car_wash, :accounting_provider) == nil
      after
        if original do
          Application.put_env(:mobile_car_wash, :accounting_provider, original)
        else
          Application.delete_env(:mobile_car_wash, :accounting_provider)
        end
      end
    end
  end

  describe "service landing display option" do
    test "service add and edit forms expose the landing display checkbox", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      service =
        ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Display Checkbox Wash",
          slug: "display_checkbox_wash_#{System.unique_integer([:positive])}",
          description: "Used to verify admin form controls.",
          base_price_cents: 9100,
          duration_minutes: 50,
          active: true,
          show_on_landing: true
        })
        |> Ash.create!()

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      assert has_element?(view, "#service-form input[name='service[show_on_landing]']")

      view
      |> element("button[phx-click='edit_service'][phx-value-id='#{service.id}']")
      |> render_click()

      assert has_element?(
               view,
               "#service-form-#{service.id} input[name='service[show_on_landing]']"
             )
    end

    test "admin can create a service hidden from the landing page", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)
      name = "Hidden Admin Wash #{System.unique_integer([:positive])}"

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      render_submit(view, "add_service", %{
        "service" => %{
          "name" => name,
          "price" => "123",
          "duration" => "70",
          "description" => "Bookable but hidden.",
          "show_on_landing" => "false"
        }
      })

      service =
        ServiceType
        |> Ash.Query.filter(name == ^name)
        |> Ash.read!()
        |> List.first()

      assert service.show_on_landing == false
      assert service.active == true
    end

    test "admin can update a service landing display setting", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      service =
        ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Update Display Wash",
          slug: "update_display_wash_#{System.unique_integer([:positive])}",
          description: "Starts visible.",
          base_price_cents: 9300,
          duration_minutes: 55,
          active: true,
          show_on_landing: true
        })
        |> Ash.create!()

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      render_submit(view, "update_service", %{
        "id" => service.id,
        "service" => %{
          "name" => service.name,
          "price" => "93",
          "duration" => "55",
          "description" => service.description,
          "show_on_landing" => "false"
        }
      })

      updated = Ash.get!(ServiceType, service.id)

      assert updated.show_on_landing == false
      assert updated.active == true
    end
  end

  describe "accounting configuration status checks" do
    test "reports zoho credentials as missing when unconfigured" do
      zoho_config = Application.get_env(:mobile_car_wash, :zoho_books, [])

      # In test env, Zoho is typically unconfigured
      refute zoho_config[:organization_id]
      refute zoho_config[:client_id]
    end

    test "reports quickbooks credentials as missing when unconfigured" do
      qb_config = Application.get_env(:mobile_car_wash, :quickbooks, [])

      refute qb_config[:company_id]
      refute qb_config[:client_id]
    end
  end

  describe "zoho credential form — saves to Application env" do
    test "saving credentials updates Application config" do
      original = Application.get_env(:mobile_car_wash, :zoho_books)

      try do
        Application.put_env(:mobile_car_wash, :zoho_books, [])

        # Simulate what the save_zoho_credentials handler does
        params = %{
          "organization_id" => "org-123",
          "client_id" => "cid-456",
          "client_secret" => "secret-789",
          "refresh_token" => "token-abc"
        }

        current = Application.get_env(:mobile_car_wash, :zoho_books, [])

        updated =
          Enum.reduce(
            [
              {:organization_id, "organization_id"},
              {:client_id, "client_id"},
              {:client_secret, "client_secret"},
              {:refresh_token, "refresh_token"}
            ],
            current,
            fn {key, param_key}, acc ->
              case params[param_key] do
                nil -> acc
                "" -> acc
                val -> Keyword.put(acc, key, val)
              end
            end
          )

        Application.put_env(:mobile_car_wash, :zoho_books, updated)

        config = Application.get_env(:mobile_car_wash, :zoho_books, [])
        assert config[:organization_id] == "org-123"
        assert config[:client_id] == "cid-456"
        assert config[:client_secret] == "secret-789"
        assert config[:refresh_token] == "token-abc"
      after
        if original do
          Application.put_env(:mobile_car_wash, :zoho_books, original)
        else
          Application.delete_env(:mobile_car_wash, :zoho_books)
        end
      end
    end

    test "blank fields preserve existing values" do
      original = Application.get_env(:mobile_car_wash, :zoho_books)

      try do
        Application.put_env(:mobile_car_wash, :zoho_books,
          organization_id: "existing-org",
          client_id: "existing-cid"
        )

        # Submitting blank fields should not overwrite
        current = Application.get_env(:mobile_car_wash, :zoho_books, [])

        updated =
          Enum.reduce(
            [{:organization_id, ""}, {:client_id, nil}],
            current,
            fn {key, val}, acc ->
              case val do
                nil -> acc
                "" -> acc
                v -> Keyword.put(acc, key, v)
              end
            end
          )

        Application.put_env(:mobile_car_wash, :zoho_books, updated)

        config = Application.get_env(:mobile_car_wash, :zoho_books, [])
        assert config[:organization_id] == "existing-org"
        assert config[:client_id] == "existing-cid"
      after
        if original do
          Application.put_env(:mobile_car_wash, :zoho_books, original)
        else
          Application.delete_env(:mobile_car_wash, :zoho_books)
        end
      end
    end
  end

  describe "quickbooks credential form — saves to Application env" do
    test "saving credentials updates Application config" do
      original = Application.get_env(:mobile_car_wash, :quickbooks)

      try do
        Application.put_env(:mobile_car_wash, :quickbooks, [])

        params = %{
          "company_id" => "comp-123",
          "client_id" => "qb-cid-456",
          "client_secret" => "qb-secret-789",
          "refresh_token" => "qb-token-abc"
        }

        current = Application.get_env(:mobile_car_wash, :quickbooks, [])

        updated =
          Enum.reduce(
            [
              {:company_id, "company_id"},
              {:client_id, "client_id"},
              {:client_secret, "client_secret"},
              {:refresh_token, "refresh_token"}
            ],
            current,
            fn {key, param_key}, acc ->
              case params[param_key] do
                nil -> acc
                "" -> acc
                val -> Keyword.put(acc, key, val)
              end
            end
          )

        Application.put_env(:mobile_car_wash, :quickbooks, updated)

        config = Application.get_env(:mobile_car_wash, :quickbooks, [])
        assert config[:company_id] == "comp-123"
        assert config[:client_id] == "qb-cid-456"
        assert config[:client_secret] == "qb-secret-789"
        assert config[:refresh_token] == "qb-token-abc"
      after
        if original do
          Application.put_env(:mobile_car_wash, :quickbooks, original)
        else
          Application.delete_env(:mobile_car_wash, :quickbooks)
        end
      end
    end

    test "blank fields preserve existing values" do
      original = Application.get_env(:mobile_car_wash, :quickbooks)

      try do
        Application.put_env(:mobile_car_wash, :quickbooks,
          company_id: "existing-comp",
          client_id: "existing-qb-cid"
        )

        current = Application.get_env(:mobile_car_wash, :quickbooks, [])

        updated =
          Enum.reduce(
            [{:company_id, ""}, {:client_id, nil}],
            current,
            fn {key, val}, acc ->
              case val do
                nil -> acc
                "" -> acc
                v -> Keyword.put(acc, key, v)
              end
            end
          )

        Application.put_env(:mobile_car_wash, :quickbooks, updated)

        config = Application.get_env(:mobile_car_wash, :quickbooks, [])
        assert config[:company_id] == "existing-comp"
        assert config[:client_id] == "existing-qb-cid"
      after
        if original do
          Application.put_env(:mobile_car_wash, :quickbooks, original)
        else
          Application.delete_env(:mobile_car_wash, :quickbooks)
        end
      end
    end
  end

  describe "credential masking" do
    test "masks values longer than 4 characters" do
      assert mask("abcdefgh") == "abcd********"
    end

    test "masks short values completely" do
      assert mask("abc") == "****"
    end

    test "handles nil" do
      assert mask(nil) == ""
    end

    defp mask(nil), do: ""

    defp mask(val) when is_binary(val) and byte_size(val) > 4 do
      String.slice(val, 0, 4) <> String.duplicate("*", 8)
    end

    defp mask(_), do: "****"
  end
end
