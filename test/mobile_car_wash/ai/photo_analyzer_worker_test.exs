defmodule MobileCarWash.AI.PhotoAnalyzerWorkerTest do
  @moduledoc """
  Covers Slice B of photo auto-tagging: every customer-uploaded
  problem-area photo enqueues a PhotoAnalyzerWorker, and the worker
  delegates to PhotoAnalyzer.analyze/1 so all the idempotency +
  feature-flag logic stays in one place.

  Before-wash photos uploaded by the tech (:before, :after,
  :step_completion) do NOT enqueue — those are handled by a separate
  before/after QA worker planned for a later feature, not this one.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.AI.{PhotoAnalyzerWorker, VisionClientMock}
  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  setup do
    VisionClientMock.init()

    original = Application.get_env(:mobile_car_wash, :ai_photo_analysis, [])
    Application.put_env(:mobile_car_wash, :ai_photo_analysis, enabled: true, max_per_appointment: 10)

    on_exit(fn ->
      Application.put_env(:mobile_car_wash, :ai_photo_analysis, original)
    end)

    {:ok, appointment} = fixture_appointment()
    %{appointment: appointment}
  end

  describe "PhotoUpload.save_file enqueue" do
    # Oban's test config is :inline, so workers run synchronously from
    # inside save_file. We assert on the observable side effect — the
    # VisionClientMock gets a call when the worker runs — instead of on
    # queue presence, which would always be empty here.
    test "runs the analyzer for customer :problem_area photos",
         %{appointment: appointment} do
      src = write_tmp_jpeg()

      {:ok, _photo} =
        PhotoUpload.save_file(
          appointment.id,
          src,
          "problem.jpg",
          :problem_area,
          uploaded_by: :customer
        )

      assert length(VisionClientMock.calls()) == 1
    end

    test "does NOT run for tech-uploaded :before photos",
         %{appointment: appointment} do
      src = write_tmp_jpeg()

      {:ok, _photo} =
        PhotoUpload.save_file(
          appointment.id,
          src,
          "before.jpg",
          :before,
          uploaded_by: :technician
        )

      assert VisionClientMock.calls() == []
    end

    test "does NOT run for :after or :step_completion photos",
         %{appointment: appointment} do
      src = write_tmp_jpeg()

      {:ok, _} = PhotoUpload.save_file(appointment.id, src, "after.jpg", :after, uploaded_by: :technician)
      {:ok, _} = PhotoUpload.save_file(appointment.id, write_tmp_jpeg(), "step.jpg", :step_completion, uploaded_by: :technician)

      assert VisionClientMock.calls() == []
    end
  end

  describe "PhotoAnalyzerWorker.perform/1" do
    test "delegates to PhotoAnalyzer and returns :ok on success",
         %{appointment: appointment} do
      {:ok, photo} =
        Photo
        |> Ash.Changeset.for_create(:upload, %{
          file_path: "uploads/worker.jpg",
          photo_type: :problem_area,
          uploaded_by: :customer,
          original_filename: "worker.jpg",
          content_type: "image/jpeg"
        })
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
        |> Ash.create()

      VisionClientMock.stub_success(photo.file_path, %{
        "is_vehicle_photo" => true,
        "body_part" => "bumper",
        "issue" => "dent",
        "severity" => "moderate",
        "confidence" => 0.9,
        "description" => "Small dent in lower front bumper"
      })

      assert :ok = perform_job(PhotoAnalyzerWorker, %{"photo_id" => photo.id})

      {:ok, reloaded} = Ash.get(Photo, photo.id)
      assert reloaded.ai_tags["issue"] == "dent"
    end

    test "returns {:error, reason} when the analyzer fails so Oban retries",
         %{appointment: appointment} do
      {:ok, photo} =
        Photo
        |> Ash.Changeset.for_create(:upload, %{
          file_path: "uploads/retry.jpg",
          photo_type: :problem_area,
          uploaded_by: :customer,
          original_filename: "retry.jpg",
          content_type: "image/jpeg"
        })
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
        |> Ash.create()

      VisionClientMock.stub_error(photo.file_path, :rate_limited)

      assert {:error, :rate_limited} =
               perform_job(PhotoAnalyzerWorker, %{"photo_id" => photo.id})
    end
  end

  # --- fixtures ---

  defp write_tmp_jpeg do
    # Minimal valid JPEG magic bytes so PhotoUpload.validate_file_content
    # doesn't reject us. 4 bytes is the size PhotoUpload reads for magic.
    path = Path.join(System.tmp_dir!(), "photo-ai-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10>> <> :crypto.strong_rand_bytes(32))
    path
  end

  defp fixture_appointment do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "photo-worker-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Photo Worker",
        phone: "+15125559900"
      })
      |> Ash.create()

    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "photo-worker-#{System.unique_integer([:positive])}",
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
        street: "9 Worker Blvd",
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
