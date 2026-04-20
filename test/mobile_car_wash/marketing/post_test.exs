defmodule MobileCarWash.Marketing.PostTest do
  @moduledoc """
  Marketing Phase 3A / Slice 1: the Post resource represents a draft
  social media post the admin composes in /admin/campaigns. It's
  adapter-agnostic — publishing routes through SocialAdapter later.

  Pinned contract:
    * Fields: title, body, channels (array of platform slugs), persona_ids
      (array of uuids), status (:draft/:scheduled/:published/:failed),
      scheduled_at, published_at, external_ids (map: slug => id),
      image_url, timestamps
    * :create accepts content fields + channels + persona_ids
    * :schedule sets scheduled_at + status=:scheduled
    * :mark_published stamps published_at + status=:published, merges
      external_ids
    * :mark_failed sets status=:failed with error_message
    * Validations: title required, at least one channel
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Marketing.Post

  describe ":create" do
    test "persists a draft post with content + channels + personas" do
      persona_id = Ecto.UUID.generate()

      {:ok, post} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Spring detail special",
          body: "Book now — 20% off through April",
          channels: ["meta", "x"],
          persona_ids: [persona_id],
          image_url: "https://x/y.png"
        })
        |> Ash.create(authorize?: false)

      assert post.title == "Spring detail special"
      assert post.channels == ["meta", "x"]
      assert post.persona_ids == [persona_id]
      assert post.status == :draft
      assert post.image_url == "https://x/y.png"
    end

    test "requires title" do
      {:error, _} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          body: "Body without title",
          channels: ["meta"]
        })
        |> Ash.create(authorize?: false)
    end

    test "requires at least one channel" do
      {:error, _} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "No channels",
          body: "Post with no outlets",
          channels: []
        })
        |> Ash.create(authorize?: false)
    end
  end

  describe ":schedule" do
    test "stamps scheduled_at and flips status" do
      {:ok, post} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Sched",
          body: "b",
          channels: ["meta"]
        })
        |> Ash.create(authorize?: false)

      future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:microsecond)

      {:ok, scheduled} =
        post
        |> Ash.Changeset.for_update(:schedule, %{scheduled_at: future})
        |> Ash.update(authorize?: false)

      assert scheduled.status == :scheduled
      assert scheduled.scheduled_at == future
    end
  end

  describe ":mark_published" do
    test "stamps published_at, status, external_ids (merging)" do
      {:ok, post} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Pub",
          body: "b",
          channels: ["meta", "x"]
        })
        |> Ash.create(authorize?: false)

      {:ok, published} =
        post
        |> Ash.Changeset.for_update(:mark_published, %{
          external_ids: %{"meta" => "fb_123", "x" => "tweet_456"}
        })
        |> Ash.update(authorize?: false)

      assert published.status == :published
      assert published.published_at != nil
      assert published.external_ids["meta"] == "fb_123"
      assert published.external_ids["x"] == "tweet_456"
    end

    test "merges new external_ids with existing" do
      {:ok, post} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Partial",
          body: "b",
          channels: ["meta", "x"]
        })
        |> Ash.create(authorize?: false)

      {:ok, post} =
        post
        |> Ash.Changeset.for_update(:mark_published, %{
          external_ids: %{"meta" => "fb_1"}
        })
        |> Ash.update(authorize?: false)

      {:ok, post} =
        post
        |> Ash.Changeset.for_update(:mark_published, %{
          external_ids: %{"x" => "tw_1"}
        })
        |> Ash.update(authorize?: false)

      assert post.external_ids["meta"] == "fb_1"
      assert post.external_ids["x"] == "tw_1"
    end
  end

  describe ":mark_failed" do
    test "sets status=:failed and error_message" do
      {:ok, post} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Fail",
          body: "b",
          channels: ["meta"]
        })
        |> Ash.create(authorize?: false)

      {:ok, failed} =
        post
        |> Ash.Changeset.for_update(:mark_failed, %{error_message: "meta: 429"})
        |> Ash.update(authorize?: false)

      assert failed.status == :failed
      assert failed.error_message == "meta: 429"
    end
  end

  describe ":read actions" do
    test ":drafts returns only drafts, newest first" do
      {:ok, a} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "A",
          body: "",
          channels: ["meta"]
        })
        |> Ash.create(authorize?: false)

      Process.sleep(5)

      {:ok, b} =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "B",
          body: "",
          channels: ["meta"]
        })
        |> Ash.create(authorize?: false)

      # Mark b as published
      {:ok, _} =
        b
        |> Ash.Changeset.for_update(:mark_published, %{external_ids: %{}})
        |> Ash.update(authorize?: false)

      drafts = Post |> Ash.Query.for_read(:drafts) |> Ash.read!(authorize?: false)

      assert Enum.map(drafts, & &1.id) == [a.id]
    end
  end
end
