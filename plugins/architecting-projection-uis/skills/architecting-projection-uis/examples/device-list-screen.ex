defmodule MyApp.Screens.DeviceList do
  @moduledoc """
  Example: Device list using :id_table for efficient row-level updates.

  Demonstrates:
  - :id_table schema type for large, mutable collections
  - Row-level state updates (only changed rows produce patches)
  - Component usage for reusable UI pieces
  - Navigation intents
  """
  use ProjectionUI, :screen

  schema do
    field :title, :string, default: "Devices"
    field :device_count, :integer, default: 0
    field :filter, :string, default: "all"
    field :devices, :id_table, columns: [
      name: :string,
      status: :string,
      last_seen: :string,
      signal_strength: :integer
    ]
  end

  @impl true
  def mount(_params, _session, state) do
    send(self(), :load_devices)
    {:ok, state}
  end

  @impl true
  def subscriptions(_params, _session) do
    ["devices:status"]
  end

  @impl true
  def handle_event("device.select", %{"arg" => device_id}, state) do
    # Navigate to device detail screen
    # The UI host will send this as a ui.route.navigate intent
    {:noreply, state}
  end

  def handle_event("devices.filter", %{"arg" => filter}, state)
      when filter in ["all", "online", "offline"] do
    filtered = apply_filter(state.assigns.all_devices, filter)
    {:noreply, state |> assign(:filter, filter) |> assign(:devices, filtered)}
  end

  def handle_event("devices.refresh", _payload, state) do
    send(self(), :load_devices)
    {:noreply, state}
  end

  def handle_event(_event, _payload, state), do: {:noreply, state}

  @impl true
  def handle_info(:load_devices, state) do
    devices = MyApp.DeviceManager.list_all()
    table = to_id_table(devices)

    {:noreply,
     state
     |> assign(:devices, table)
     |> assign(:device_count, length(devices))}
  end

  # Single device status update — only this row gets patched
  def handle_info({:device_status, device_id, new_status}, state) do
    {:noreply,
     update(state, :devices, fn table ->
       if Map.has_key?(table.by_id, device_id) do
         put_in(table, [:by_id, device_id, :status], new_status)
         |> put_in([:by_id, device_id, :last_seen], format_time(DateTime.utc_now()))
       else
         table
       end
     end)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp to_id_table(devices) do
    order = Enum.map(devices, & &1.id)

    by_id =
      Map.new(devices, fn d ->
        {d.id,
         %{
           name: d.name,
           status: to_string(d.status),
           last_seen: format_time(d.last_seen),
           signal_strength: d.signal_strength
         }}
      end)

    %{order: order, by_id: by_id}
  end

  defp apply_filter(devices, "all"), do: devices

  defp apply_filter(devices, filter) do
    filtered_ids = Enum.filter(devices.order, fn id ->
      devices.by_id[id].status == filter
    end)

    %{devices | order: filtered_ids}
  end

  defp format_time(nil), do: "never"
  defp format_time(dt), do: Calendar.strftime(dt, "%H:%M:%S")
end
