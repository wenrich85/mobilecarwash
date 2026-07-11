defmodule MobileCarWash.Operations.PhotoUploadExternalTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  require Ash.Query

  defp create_appointment do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ext-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Ext Customer",
        phone: "+15125550801"
      })
      |> Ash.create()

    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Ext Wash",
        slug: "ext-#{System.unique_integer([:positive])}",
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
        street: "1 Ext",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
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

    appt
  end

  describe "object_key/3" do
    test "builds the appointments/<id>/<type>_<uuid><ext> shape" do
      key = PhotoUpload.object_key("abc-123", :before, "IMG 1.JPG")

      assert key =~ ~r|^appointments/abc-123/before_[0-9a-f-]{36}\.jpg$|
    end
  end

  describe "save_external_file/5" do
    test "creates a Photo row whose file_path is the object key" do
      appt = create_appointment()
      key = PhotoUpload.object_key(appt.id, :before, "front.jpg")

      assert {:ok, photo} =
               PhotoUpload.save_external_file(appt.id, key, "front.jpg", :before,
                 uploaded_by: :technician,
                 car_part: :front
               )

      assert photo.file_path == key
      assert photo.photo_type == :before
      assert photo.car_part == :front
      assert photo.uploaded_by == :technician
      assert photo.content_type == "image/jpeg"
    end

    test "replaces an existing photo in the same slot" do
      appt = create_appointment()
      key1 = PhotoUpload.object_key(appt.id, :before, "a.jpg")
      key2 = PhotoUpload.object_key(appt.id, :before, "b.jpg")

      {:ok, _first} =
        PhotoUpload.save_external_file(appt.id, key1, "a.jpg", :before, car_part: :front)

      {:ok, second} =
        PhotoUpload.save_external_file(appt.id, key2, "b.jpg", :before, car_part: :front)

      live =
        Photo
        |> Ash.Query.filter(
          appointment_id == ^appt.id and photo_type == :before and car_part == :front and
            is_nil(deleted_at)
        )
        |> Ash.read!(authorize?: false)

      assert [%{id: id}] = live
      assert id == second.id
    end

    test "enqueues AI analysis for customer problem-area photos only" do
      appt = create_appointment()

      Oban.Testing.with_testing_mode(:manual, fn ->
        key = PhotoUpload.object_key(appt.id, :problem_area, "spot.jpg")

        {:ok, _photo} =
          PhotoUpload.save_external_file(appt.id, key, "spot.jpg", :problem_area,
            uploaded_by: :customer
          )

        assert_enqueued(worker: MobileCarWash.AI.PhotoAnalyzerWorker)

        key2 = PhotoUpload.object_key(appt.id, :before, "front.jpg")

        {:ok, tech_photo} =
          PhotoUpload.save_external_file(appt.id, key2, "front.jpg", :before,
            uploaded_by: :technician,
            car_part: :front
          )

        refute_enqueued(
          worker: MobileCarWash.AI.PhotoAnalyzerWorker,
          args: %{photo_id: tech_photo.id}
        )
      end)
    end

    test "returns the existing photo for a repeated idempotency key" do
      appt = create_appointment()
      key = PhotoUpload.object_key(appt.id, :before, "front.jpg")

      {:ok, first} =
        PhotoUpload.save_external_file(appt.id, key, "front.jpg", :before,
          car_part: :front,
          idempotency_key: "idem-1"
        )

      {:ok, second} =
        PhotoUpload.save_external_file(appt.id, key, "front.jpg", :before,
          car_part: :front,
          idempotency_key: "idem-1"
        )

      assert first.id == second.id
    end

    test "rejects extensions outside the allow-list" do
      appt = create_appointment()

      assert {:error, "Invalid image file"} =
               PhotoUpload.save_external_file(
                 appt.id,
                 "appointments/#{appt.id}/before_x.gif",
                 "x.gif",
                 :before,
                 car_part: :front
               )
    end
  end

  describe "external_uploads?/0" do
    test "true only when the backend is :s3" do
      previous = Application.get_env(:mobile_car_wash, :photo_storage, :local)
      on_exit(fn -> Application.put_env(:mobile_car_wash, :photo_storage, previous) end)

      Application.put_env(:mobile_car_wash, :photo_storage, :local)
      refute PhotoUpload.external_uploads?()

      Application.put_env(:mobile_car_wash, :photo_storage, :s3)
      assert PhotoUpload.external_uploads?()
    end
  end
end
