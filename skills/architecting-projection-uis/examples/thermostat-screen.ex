defmodule MyApp.Screens.Thermostat do
  @moduledoc """
  Example: Thermostat control screen for an embedded HVAC controller.

  Demonstrates:
  - Typed schema with multiple field types
  - PubSub subscriptions for live sensor data
  - Intent handling for user controls
  - Async data loading in mount
  """
  use ProjectionUI, :screen

  schema do
    field :title, :string, default: "Thermostat"
    field :current_temp, :float, default: 0.0
    field :target_temp, :float, default: 22.0
    field :humidity, :float, default: 0.0
    field :mode, :string, default: "off"
    field :is_heating, :bool, default: false
    field :is_cooling, :bool, default: false
    field :schedule_active, :bool, default: false
    field :status_text, :string, default: "Initializing..."
  end

  @impl true
  def mount(_params, _session, state) do
    # Defer heavy work — render defaults immediately
    send(self(), :load_current_state)

    {:ok, state}
  end

  @impl true
  def subscriptions(_params, _session) do
    ["sensors:temperature", "sensors:humidity", "hvac:status"]
  end

  @impl true
  def handle_event("thermostat.set_target", %{"arg" => temp_str}, state) do
    case Float.parse(temp_str) do
      {temp, _} when temp >= 15.0 and temp <= 30.0 ->
        MyApp.HVAC.set_target(temp)
        {:noreply, state |> assign(:target_temp, temp)}

      _ ->
        {:noreply, state |> assign(:status_text, "Invalid temperature")}
    end
  end

  def handle_event("thermostat.mode", %{"arg" => mode}, state)
      when mode in ["heat", "cool", "auto", "off"] do
    MyApp.HVAC.set_mode(mode)
    {:noreply, state |> assign(:mode, mode)}
  end

  def handle_event("thermostat.temp_up", _payload, state) do
    new_target = min(state.assigns.target_temp + 0.5, 30.0)
    MyApp.HVAC.set_target(new_target)
    {:noreply, state |> assign(:target_temp, new_target)}
  end

  def handle_event("thermostat.temp_down", _payload, state) do
    new_target = max(state.assigns.target_temp - 0.5, 15.0)
    MyApp.HVAC.set_target(new_target)
    {:noreply, state |> assign(:target_temp, new_target)}
  end

  # Catch-all — required for robustness
  def handle_event(_event, _payload, state), do: {:noreply, state}

  @impl true
  def handle_info(:load_current_state, state) do
    hvac_state = MyApp.HVAC.current_state()

    {:noreply,
     state
     |> assign(:current_temp, hvac_state.temperature)
     |> assign(:target_temp, hvac_state.target)
     |> assign(:humidity, hvac_state.humidity)
     |> assign(:mode, hvac_state.mode)
     |> assign(:is_heating, hvac_state.heating?)
     |> assign(:is_cooling, hvac_state.cooling?)
     |> assign(:status_text, format_status(hvac_state))}
  end

  def handle_info({:sensor_reading, :temperature, value}, state) do
    {:noreply,
     state
     |> assign(:current_temp, value)
     |> assign(:status_text, format_status_from_state(state.assigns, value))}
  end

  def handle_info({:sensor_reading, :humidity, value}, state) do
    {:noreply, state |> assign(:humidity, value)}
  end

  def handle_info({:hvac_status, status}, state) do
    {:noreply,
     state
     |> assign(:is_heating, status.heating?)
     |> assign(:is_cooling, status.cooling?)
     |> assign(:mode, status.mode)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp format_status(%{mode: "off"}), do: "System off"
  defp format_status(%{heating?: true}), do: "Heating..."
  defp format_status(%{cooling?: true}), do: "Cooling..."
  defp format_status(_), do: "Idle"

  defp format_status_from_state(%{mode: "off"}, _temp), do: "System off"
  defp format_status_from_state(%{target_temp: target}, temp) when temp < target - 0.5, do: "Heating..."
  defp format_status_from_state(%{target_temp: target}, temp) when temp > target + 0.5, do: "Cooling..."
  defp format_status_from_state(_, _), do: "At target"
end
