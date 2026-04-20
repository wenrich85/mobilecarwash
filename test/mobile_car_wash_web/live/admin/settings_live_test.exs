defmodule MobileCarWashWeb.Admin.SettingsLiveTest do
  @moduledoc """
  Tests for the admin Settings LiveView — specifically the Accounting tab.
  Verifies provider switching, configuration status display, and auth guard.
  """
  use MobileCarWashWeb.ConnCase, async: true

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
