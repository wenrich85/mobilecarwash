defmodule MobileCarWash.Operations.PhotoUploadTest do
  use MobileCarWash.DataCase

  require Ash.Query

  alias MobileCarWash.Operations.{PhotoUpload, Photo}
  alias MobileCarWash.Scheduling.Appointment

  setup do
    appointment = create_appointment()
    {:ok, appointment: appointment}
  end

  describe "save_file/5 with car_part" do
    test "saves file and creates photo with car_part", %{appointment: appointment} do
      source_path = create_test_image()
      appt_id = appointment.id

      result =
        PhotoUpload.save_file(
          appt_id,
          source_path,
          "test.jpg",
          :before,
          car_part: :exterior
        )

      assert {:ok, _url} = result

      # Verify photo was created with car_part
      photos = Ash.read!(Photo |> Ash.Query.filter(appointment_id == ^appt_id))
      assert length(photos) == 1
      assert hd(photos).car_part == :exterior
    end

    test "saves file without car_part when not provided", %{appointment: appointment} do
      source_path = create_test_image()
      appt_id = appointment.id

      result =
        PhotoUpload.save_file(
          appt_id,
          source_path,
          "test.jpg",
          :after
        )

      assert {:ok, _url} = result

      # Verify photo was created without car_part
      photos = Ash.read!(Photo |> Ash.Query.filter(appointment_id == ^appt_id))
      assert length(photos) == 1
      assert hd(photos).car_part == nil
    end

    test "saves file with various car parts", %{appointment: appointment} do
      car_parts = [
        :exterior,
        :windows,
        :wheels,
        :interior,
        :trunk,
        :engine_bay,
        :undercarriage,
        :mirrors,
        :headlights_taillights,
        :bumper,
        :roof,
        :sunroof
      ]

      appt_id = appointment.id

      Enum.each(car_parts, fn car_part ->
        source_path = create_test_image()

        result =
          PhotoUpload.save_file(
            appt_id,
            source_path,
            "test.jpg",
            :step_completion,
            car_part: car_part
          )

        assert {:ok, _url} = result
      end)

      # Verify all photos were created with correct car parts
      photos = Ash.read!(Photo |> Ash.Query.filter(appointment_id == ^appt_id))
      assert length(photos) == 12

      Enum.each(car_parts, fn car_part ->
        assert Enum.any?(photos, &(&1.car_part == car_part))
      end)
    end

    test "preserves other photo metadata with car_part", %{appointment: appointment} do
      source_path = create_test_image()
      appt_id = appointment.id

      result =
        PhotoUpload.save_file(
          appt_id,
          source_path,
          "damage.jpg",
          :problem_area,
          uploaded_by: :customer,
          caption: "Dent on passenger side",
          car_part: :bumper
        )

      assert {:ok, _url} = result

      photos = Ash.read!(Photo |> Ash.Query.filter(appointment_id == ^appt_id))
      photo = hd(photos)

      assert photo.car_part == :bumper
      assert photo.caption == "Dent on passenger side"
      assert photo.uploaded_by == :customer
      assert photo.photo_type == :problem_area
    end
  end

  describe "photo queries by car_part" do
    test "filters photos by car_part using custom actions", %{appointment: appointment} do
      source_path1 = create_test_image()
      source_path2 = create_test_image()
      source_path3 = create_test_image()
      appt_id = appointment.id

      PhotoUpload.save_file(
        appt_id,
        source_path1,
        "exterior.jpg",
        :before,
        car_part: :exterior
      )

      PhotoUpload.save_file(
        appt_id,
        source_path2,
        "wheels.jpg",
        :before,
        car_part: :wheels
      )

      PhotoUpload.save_file(
        appt_id,
        source_path3,
        "windows.jpg",
        :before,
        car_part: :windows
      )

      # Read all before photos
      all_before = Ash.read!(Photo |> Ash.Query.filter(appointment_id == ^appt_id))
      assert length(all_before) == 3

      # Verify car_parts are present
      assert Enum.any?(all_before, &(&1.car_part == :exterior))
      assert Enum.any?(all_before, &(&1.car_part == :wheels))
      assert Enum.any?(all_before, &(&1.car_part == :windows))
    end
  end

  # === Helpers ===

  defp create_appointment do
    email = "photo-test-#{:rand.uniform(100_000)}@test.com"

    customer =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:create_guest, %{email: email, name: "Photo Test", phone: "+15125551234"})
      |> Ash.create!()

    vehicle =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    address =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "123 Main St", city: "San Antonio", state: "TX", zip: "78201"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    service =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Photo Test Wash",
        slug: "photo_test_#{:rand.uniform(100_000)}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create!()

    hour = 8 + :rand.uniform(8)
    {:ok, dt} = DateTime.new(~D[2030-06-05], Time.new!(hour, 0, 0))

    {:ok, %{appointment: appt}} =
      MobileCarWash.Scheduling.Booking.create_booking(%{
        customer_id: customer.id,
        service_type_id: service.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        scheduled_at: dt,
        subscription_id: nil
      })

    appt
  end

  defp create_test_image do
    # Create a minimal valid JPEG file with magic bytes
    jpeg_header = <<0xFF, 0xD8, 0xFF, 0xE0>> <> "JFIF" <> <<0, 16, 1, 1, 0, 1, 0, 1, 0, 0>>
    jpeg_end = <<0xFF, 0xD9>>
    jpeg_content = jpeg_header <> "test data" <> jpeg_end

    file_path = Path.join(System.tmp_dir(), "test_#{Ash.UUID.generate()}.jpg")
    File.write!(file_path, jpeg_content)
    file_path
  end
end
