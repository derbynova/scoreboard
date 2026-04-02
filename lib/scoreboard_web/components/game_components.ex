defmodule ScoreboardWeb.GameComponents do
  @moduledoc """
  Game-specific UI components for the DerbyNova scoreboard operator view.

  Provides reusable function components for displaying game state (TopBar, GameBanner)
  and controls (ControlPanel, ScoreControls, TeamActions). Components are designed
  for reuse across operator, audience, and overlay views.
  """
  use Phoenix.Component
  use Gettext, backend: ScoreboardWeb.Gettext
  alias ScoreboardWeb.Helpers.Clock

  defp phase_color(:initial), do: "text-base-content/50"
  defp phase_color(:lineup), do: "text-amber-400"
  defp phase_color(:jam_running), do: "text-emerald-400"
  defp phase_color(:timeout), do: "text-sky-400"
  defp phase_color(:halftime), do: "text-slate-400"
  defp phase_color(:final), do: "text-base-content/50"

  defp phase_label(:initial), do: "Pregame"
  defp phase_label(:lineup), do: "Lineup"
  defp phase_label(:jam_running), do: "Jam"
  defp phase_label(:timeout), do: "Timeout"
  defp phase_label(:halftime), do: "Halftime"
  defp phase_label(:final), do: "Final"

  def active_clock(snapshot) do
    case snapshot.phase do
      :initial ->
        {"", 0, false}

      :lineup ->
        {phase_label(snapshot.phase), snapshot.lineup_clock_s, snapshot.lineup_clock_running}

      :jam_running ->
        {phase_label(snapshot.phase), snapshot.jam_clock_s, snapshot.jam_clock_running}

      :timeout ->
        {phase_label(snapshot.phase), snapshot.timeout_clock_s, snapshot.timeout_clock_running}

      :halftime ->
        {"Intermission", snapshot.period_clock_s, false}

      :final ->
        {"", 0, false}
    end
  end

  @doc """
  Renders the top bar with game ID, period/jam info, and audience link.
  """
  attr :game_id, :string, required: true
  attr :snapshot, :map, required: true

  def top_bar(assigns) do
    ~H"""
    <div class="flex justify-between items-center bg-base-300 rounded-t-lg px-3 py-1.5">
      <span class="text-sm font-mono text-base-content/70">{@game_id}</span>
      <span class="text-sm font-medium">
        P{@snapshot.period} · J{@snapshot.jam_number} · {Clock.format_clock(@snapshot.period_clock_s)}
      </span>
      <.link navigate={"/game/#{@game_id}"} class="text-sm text-primary hover:underline">
        Audience View
      </.link>
    </div>
    """
  end

  @doc """
  Renders timeout dots showing available timeouts.
  Dots are filled from the left, dimmed from the right based on used count.
  """
  attr :used, :integer, default: 0
  attr :total, :integer, default: 3
  attr :color, :string, required: true

  def timeout_dots(assigns) do
    ~H"""
    <div class="flex gap-1">
      <span
        :for={i <- 1..@total}
        class={"w-2 h-2 rounded-full #{@color} #{i > @total - @used && "opacity-30"}"}
      >
      </span>
    </div>
    """
  end

  @doc """
  Renders a clock display with label and formatted time.
  """
  attr :label, :string, default: ""
  attr :seconds, :integer, default: 0
  attr :running, :boolean, default: false
  attr :color, :string, default: "text-base-content"

  def clock_display(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <span :if={@label != ""} class={"text-xs uppercase tracking-widest #{@color}"}>
        {@label}
      </span>
      <span class={"text-5xl font-bold tabular-nums leading-none #{@color} #{@running && "animate-pulse"}"}>
        {Clock.format_clock(@seconds)}
      </span>
    </div>
    """
  end

  @doc """
  Renders a team display with name, score, timeout dots, and OR badge.
  """
  attr :name, :string, required: true
  attr :score, :integer, required: true
  attr :label_color, :string, required: true
  attr :dot_color, :string, required: true
  attr :to_used, :integer, default: 0
  attr :or_count, :integer, default: 1

  def team_display(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <span class={"text-sm font-semibold #{@label_color}"}>
        {@name}
      </span>
      <span class="text-6xl font-bold tabular-nums text-base-content">
        {@score}
      </span>
      <div class="flex items-center gap-2">
        <.timeout_dots used={@to_used} total={3} color={@dot_color} />
        <span :if={@or_count > 0} class="text-xs font-bold text-purple-400">
          OR#{@or_count}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders the game banner with team displays and central clock.
  """
  attr :snapshot, :map, required: true
  attr :variant, :atom, values: [:compact, :full, :overlay], default: :compact

  def game_banner(assigns) do
    {label, seconds, running} = active_clock(assigns.snapshot)

    assigns =
      assign(assigns,
        clock_label: label,
        clock_seconds: seconds,
        clock_running: running,
        clock_color: phase_color(assigns.snapshot.phase)
      )

    ~H"""
    <div class="grid grid-cols-3 items-center bg-base-200">
      <.team_display
        name="Home"
        score={@snapshot.score_home}
        label_color="text-red-400"
        dot_color="bg-red-500"
        to_used={0}
        or_count={1}
      />
      <.clock_display
        label={@clock_label}
        seconds={@clock_seconds}
        running={@clock_running}
        color={@clock_color}
      />
      <.team_display
        name="Away"
        score={@snapshot.score_away}
        label_color="text-blue-400"
        dot_color="bg-blue-500"
        to_used={0}
        or_count={1}
      />
    </div>
    """
  end

  @doc """
  Renders score control buttons for a team.
  """
  attr :team, :string, required: true
  attr :bg_base, :string, required: true
  attr :bg_dim, :string, required: true
  attr :text_color, :string, required: true

  def score_controls(assigns) do
    ~H"""
    <div class="flex gap-1">
      <button
        phx-click="score"
        phx-value-team={@team}
        phx-value-points="-1"
        class={"flex-1 py-2.5 rounded-md font-bold text-sm #{@bg_dim} #{@text_color}"}
      >
        -1
      </button>
      <button
        phx-click="score"
        phx-value-team={@team}
        phx-value-points="1"
        class={"flex-1 py-2.5 rounded-md font-bold text-sm #{@bg_base} #{@text_color}"}
      >
        +1
      </button>
      <button
        phx-click="score"
        phx-value-team={@team}
        phx-value-points="2"
        class={"flex-1 py-2.5 rounded-md font-bold text-sm #{@bg_base} #{@text_color}"}
      >
        +2
      </button>
      <button
        phx-click="score"
        phx-value-team={@team}
        phx-value-points="3"
        class={"flex-1 py-2.5 rounded-md font-bold text-sm #{@bg_base} #{@text_color}"}
      >
        +3
      </button>
      <button
        phx-click="score"
        phx-value-team={@team}
        phx-value-points="4"
        class={"flex-1 py-2.5 rounded-md font-bold text-sm #{@bg_base} #{@text_color}"}
      >
        +4
      </button>
    </div>
    """
  end

  @doc """
  Renders team action buttons (TO and OR).
  """
  attr :team, :string, required: true
  attr :bg_to, :string, required: true
  attr :bg_to_border, :string, required: true
  attr :text_to, :string, required: true

  def team_actions(assigns) do
    ~H"""
    <div class="flex gap-1">
      <button
        phx-click="call_timeout"
        phx-value-team={@team}
        class={"flex-1 py-1.5 rounded-md text-xs font-bold #{@bg_to} #{@bg_to_border} border #{@text_to}"}
      >
        TO
      </button>
      <button
        phx-click="call_or"
        phx-value-team={@team}
        class={"flex-1 py-1.5 rounded-md text-xs font-bold #{@bg_to} #{@bg_to_border} border #{@text_to}"}
      >
        OR
      </button>
    </div>
    """
  end

  @doc """
  Renders the control panel with score controls, team actions, and phase-specific CTA.
  """
  attr :snapshot, :map, required: true

  def control_panel(assigns) do
    ~H"""
    <div class="border-t border-base-300 pt-2">
      <div class="grid grid-cols-[1fr_auto_1fr] gap-2">
        <!-- Home side -->
        <div class="flex flex-col gap-1">
          <.score_controls
            team="home"
            bg_base="bg-red-500"
            bg_dim="bg-red-900"
            text_color="text-red-300"
          />
          <.team_actions
            team="home"
            bg_to="bg-red-950"
            bg_to_border="border-red-800"
            text_to="text-red-300"
          />
        </div>
        
    <!-- Center CTA -->
        <div class="flex items-center justify-center">
          {render_center_cta(assigns)}
        </div>
        
    <!-- Away side -->
        <div class="flex flex-col gap-1">
          <.score_controls
            team="away"
            bg_base="bg-blue-500"
            bg_dim="bg-blue-900"
            text_color="text-blue-300"
          />
          <.team_actions
            team="away"
            bg_to="bg-blue-950"
            bg_to_border="border-blue-800"
            text_to="text-blue-300"
          />
        </div>
      </div>
    </div>
    """
  end

  defp render_center_cta(%{snapshot: %{phase: :initial}} = assigns) do
    ~H"""
    <button
      phx-click="start_period"
      class="px-6 py-3 rounded-lg font-bold text-lg bg-primary text-primary-content"
    >
      Start Period 1
    </button>
    """
  end

  defp render_center_cta(%{snapshot: %{phase: :lineup}} = assigns) do
    ~H"""
    <button
      phx-click="start_jam"
      class="px-6 py-3 rounded-lg font-bold text-lg bg-amber-400 text-black"
    >
      Start Jam <kbd class="kbd kbd-sm ml-2">Space</kbd>
    </button>
    """
  end

  defp render_center_cta(%{snapshot: %{phase: :jam_running}} = assigns) do
    ~H"""
    <button
      phx-click="end_jam"
      class="px-6 py-3 rounded-lg font-bold text-lg bg-emerald-500 text-white"
    >
      End Jam <kbd class="kbd kbd-sm ml-2">Space</kbd>
    </button>
    """
  end

  defp render_center_cta(%{snapshot: %{phase: :timeout}} = assigns) do
    ~H"""
    <button
      phx-click="end_timeout"
      class="px-6 py-3 rounded-lg font-bold text-lg bg-sky-500 text-white"
    >
      End Timeout <kbd class="kbd kbd-sm ml-2">E</kbd>
    </button>
    """
  end

  defp render_center_cta(%{snapshot: %{phase: :halftime}} = assigns) do
    ~H"""
    <button
      phx-click="start_period"
      class="px-6 py-3 rounded-lg font-bold text-lg bg-primary text-primary-content"
    >
      Start Period 2
    </button>
    """
  end

  defp render_center_cta(%{snapshot: %{phase: :final}} = assigns) do
    ~H"""
    <span class="text-base-content/60 font-bold text-lg px-6">Game Over</span>
    """
  end
end
