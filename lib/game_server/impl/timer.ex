defmodule GameServer.Impl.Timer do
  defstruct [:duration, :started_at, accumulated: 0, running: false]

  def new(duration_ms), do: %__MODULE__{duration: duration_ms}

  def start(t, now), do: %{t | started_at: now, running: true}

  def stop(t, now), do: %{t | accumulated: elapsed(t, now), started_at: nil, running: false}

  def reset(t, duration_ms \\ nil) do
    %{t | duration: duration_ms || t.duration, accumulated: 0, started_at: nil, running: false}
  end

  def elapsed(%{running: false, accumulated: acc}, _now), do: acc
  def elapsed(%{running: true, started_at: s, accumulated: acc}, now), do: acc + (now - s)

  def remaining(t, now), do: max(0, t.duration - elapsed(t, now))

  def finished?(t, now), do: remaining(t, now) == 0
end
