# One-time backfill: populate zone on existing addresses
# Run with: mix run priv/repo/backfill_zones.exs

alias MobileCarWash.Fleet.Address
alias MobileCarWash.Zones

addresses = Ash.read!(Address)
IO.puts("Backfilling zones for #{length(addresses)} addresses...")

Enum.each(addresses, fn addr ->
  zone = Zones.zone_for_zip(addr.zip)

  if zone && addr.zone != zone do
    addr
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:zone, zone)
    |> Ash.update!()
    IO.puts("  #{addr.zip} → #{zone}")
  end
end)

IO.puts("Done.")
