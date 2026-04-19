defmodule MobileCarWash.AI.PhotoAnalyzerTest do
  @moduledoc """
  Covers Slice A of photo auto-tagging: the PhotoAnalyzer orchestrator
  loads a Photo, calls the configured VisionClient, and persists the
  structured response on the row.

  Feature-flag gated. API calls in tests go through the ETS-backed
  VisionClientMock (see test/support/vision_client_mock.ex).
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.AI.{PhotoAnalyzer, VisionClientMock}
  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  setup do
    VisionClientMock.init()
    original = Application.get_env(:mobile_car_wash, :ai_photo_analysis, [])

    on_exit(fn ->
      Application.put_env(:mobile_car_wash, :ai_photo_analysis, original)
    end)

    {:ok, appointment} = fixture_appointment()

    {:ok, photo} =
      Photo
      |> Ash.Changeset.for_create(:upload, %{
        file_path: "uploads/test.jpg",
        photo_type: :problem_area,
        uploaded_by: :customer,
        original_filename: "test.jpg",
        content_type: "image/jpeg"
      })
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    %{photo: photo, appointment: appointment}
  end

  describe "analyze/1" do
    test "applies a valid AI response to the photo row", %{photo: photo} do
      enable_feature()

      VisionClientMock.stub_success(
        photo.file_path,
        %{
          "is_vehicle_photo" => true,
          "body_part" => "bumper",
          "issue" => "scratch",
          "severity" => "light",
          "confidence" => 0.87,
          "description" => "Light scratch on lower rear bumper"
        }
      )

      :ok = PhotoAnalyzer.analyze(photo.id)

      {:ok, reloaded} = Ash.get(Photo, photo.id)
      assert reloaded.ai_tags["body_part"] == "bumper"
      assert reloaded.ai_tags["confidence"] == 0.87
      assert reloaded.ai_processed_at
    end

    test "broadcasts {:ai_tags, photo} on the per-photo topic after applying",
         %{photo: photo} do
      enable_feature()
      Phoenix.PubSub.subscribe(MobileCarWash.PubSub, "photo:#{photo.id}:ai")

      VisionClientMock.stub_success(photo.file_path, %{
        "is_vehicle_photo" => true,
        "body_part" => "wheels",
        "issue" => "dirt",
        "severity" => "light",
        "confidence" => 0.8,
        "description" => "Dust on rim"
      })

      :ok = PhotoAnalyzer.analyze(photo.id)

      assert_receive {:ai_tags, updated}, 500
      assert updated.id == photo.id
      assert updated.ai_tags["body_part"] == "wheels"
    end

    test "is idempotent — second call skips the already-processed photo",
         %{photo: photo} do
      enable_feature()

      VisionClientMock.stub_success(photo.file_path, %{
        "is_vehicle_photo" => true,
        "body_part" => "wheels",
        "issue" => "dirt",
        "severity" => "light",
        "confidence" => 0.7,
        "description" => "Dust build-up on front driver wheel"
      })

      :ok = PhotoAnalyzer.analyze(photo.id)
      first_pass = length(VisionClientMock.calls())

      :ok = PhotoAnalyzer.analyze(photo.id)
      second_pass = length(VisionClientMock.calls())

      assert first_pass == 1
      assert second_pass == 1, "second analyze/1 must not re-hit the API"
    end

    test "no-ops when the feature flag is off", %{photo: photo} do
      disable_feature()

      :ok = PhotoAnalyzer.analyze(photo.id)

      assert VisionClientMock.calls() == []

      {:ok, reloaded} = Ash.get(Photo, photo.id)
      assert is_nil(reloaded.ai_tags)
      assert is_nil(reloaded.ai_processed_at)
    end

    test "returns {:error, ...} when the VisionClient errors — photo stays unlabeled",
         %{photo: photo} do
      enable_feature()
      VisionClientMock.stub_error(photo.file_path, :rate_limited)

      assert {:error, :rate_limited} = PhotoAnalyzer.analyze(photo.id)

      {:ok, reloaded} = Ash.get(Photo, photo.id)
      assert is_nil(reloaded.ai_tags)
      assert is_nil(reloaded.ai_processed_at)
    end
  end

  defp enable_feature do
    Application.put_env(:mobile_car_wash, :ai_photo_analysis, enabled: true, max_per_appointment: 10)
  end

  defp disable_feature do
    Application.put_env(:mobile_car_wash, :ai_photo_analysis, enabled: false)
  end

  defp fixture_appointment do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "photo-ai-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "AI Photo Customer",
        phone: "+15125558800"
      })
      |> Ash.create()

    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "ai-photo-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "5 AI Way",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    MobileCarWash.Scheduling.Appointment
    |> Ash.Changeset.for_create(:book, %{
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      service_type_id: service.id,
      scheduled_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
      price_cents: 5_000,
      duration_minutes: 45
    })
    |> Ash.create()
  end
end
