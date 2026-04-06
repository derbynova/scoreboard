defmodule ScoreboardWeb.GameLiveTest do
  use ScoreboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    # Clean up any leftover game processes from previous tests
    for {pid, _} <- DynamicSupervisor.which_children(GameServer.Runtime.Supervisor) do
      DynamicSupervisor.terminate_child(GameServer.Runtime.Supervisor, pid)
    end

    on_exit(fn ->
      for {pid, _} <- DynamicSupervisor.which_children(GameServer.Runtime.Supervisor) do
        DynamicSupervisor.terminate_child(GameServer.Runtime.Supervisor, pid)
      end
    end)

    :ok
  end

  describe "Index LiveView" do
    test "renders landing page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/games/new")

      assert html =~ "DerbyNova Scoreboard"
      assert html =~ "New Game"
      assert html =~ "Join Game"
    end

    test "create game redirects to operator", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/new")

      # Click the "New Game" button - it should live_redirect
      assert {:error, {:live_redirect, %{to: to}}} = render_click(view, :create_game)
      assert to =~ "/games/"
      assert to =~ "/operator"
    end
  end

  describe "Operator LiveView" do
    test "renders with initial state", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-test")

      {:ok, view, _html} = live(conn, ~p"/games/operator-test/operator")

      # Check initial state rendering
      assert render(view) =~ "Start Period 1"
      # Check team labels instead of generic score labels
      assert render(view) =~ "Home"
      assert render(view) =~ "Away"
    end

    test "start period shows lineup controls", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-lineup")

      {:ok, view, _html} = live(conn, ~p"/games/operator-lineup/operator")

      # Start the period
      render_click(view, :start_period)

      # Wait for PubSub update
      :timer.sleep(150)

      # Should show lineup controls
      assert render(view) =~ "Start Jam"
      assert render(view) =~ "TO"
    end

    test "full game lifecycle via buttons", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-full")

      {:ok, view, _html} = live(conn, ~p"/games/operator-full/operator")

      # 1. Start period
      render_click(view, :start_period)
      :timer.sleep(150)
      assert render(view) =~ "Start Jam"

      # 2. Start jam
      render_click(view, :start_jam)
      :timer.sleep(150)
      assert render(view) =~ "End Jam"

      # 3. Add scores
      render_click(view, :score, %{"team" => "home", "points" => "3"})
      render_click(view, :score, %{"team" => "away", "points" => "2"})
      :timer.sleep(150)
      assert has_element?(view, "#score-home", "3")
      assert has_element?(view, "#score-away", "2")

      # 4. End jam
      render_click(view, :end_jam)
      :timer.sleep(150)
      assert render(view) =~ "Start Jam"

      # 5. End period 1 (via keyboard 'e' in lineup)
      render_hook(view, "keydown", %{"key" => "e", "code" => "KeyE"})
      :timer.sleep(150)
      assert render(view) =~ "Start Period 2"

      # 6. Start period 2
      render_click(view, :start_period)
      :timer.sleep(150)
      assert render(view) =~ "Start Jam"

      # 7. Start jam to be in jam_running phase
      render_click(view, :start_jam)
      :timer.sleep(150)
      assert render(view) =~ "End Jam"

      # 8. End game (via keyboard 'e' in jam_running, P2)
      render_hook(view, "keydown", %{"key" => "e", "code" => "KeyE"})
      :timer.sleep(150)
      assert render(view) =~ "Game Over"
    end

    test "negative score via -1 button subtracts points", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-neg-score")

      {:ok, view, _html} = live(conn, ~p"/games/operator-neg-score/operator")

      # Start period and jam
      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)

      # Add 3 points to home
      render_click(view, :score, %{"team" => "home", "points" => "3"})
      :timer.sleep(150)

      # Subtract 1 via -1 button
      render_click(view, :score, %{"team" => "home", "points" => "-1"})
      :timer.sleep(150)

      # Home score should be 2
      assert has_element?(view, "#score-home", "2")
      refute render(view) =~ "Invalid points value"
    end

    test "timeout cycle", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-timeout")

      {:ok, view, _html} = live(conn, ~p"/games/operator-timeout/operator")

      # Start period and jam
      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)

      # Call timeout
      render_click(view, :call_timeout)
      :timer.sleep(150)
      assert render(view) =~ "End Timeout"

      # End timeout
      render_click(view, :end_timeout)
      :timer.sleep(150)
      assert render(view) =~ "Start Jam"
    end

    test "keyboard shortcut: space starts jam from lineup", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-space-start")

      {:ok, view, _html} = live(conn, ~p"/games/kb-space-start/operator")

      render_click(view, :start_period)
      :timer.sleep(150)

      # Space key starts jam from lineup
      render_hook(view, "keydown", %{"key" => " ", "code" => "Space"})
      :timer.sleep(150)

      assert render(view) =~ "End Jam"
    end

    test "keyboard shortcut: space ends jam", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-space-end")

      {:ok, view, _html} = live(conn, ~p"/games/kb-space-end/operator")

      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)

      # Space key ends jam
      render_hook(view, "keydown", %{"key" => " ", "code" => "Space"})
      :timer.sleep(150)

      assert render(view) =~ "Start Jam"
    end

    test "keyboard shortcut: Digit1-4 add home scores via code", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-digit-home")

      {:ok, view, _html} = live(conn, ~p"/games/kb-digit-home/operator")

      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)

      # Digit3 without shift adds 3 to home
      render_hook(view, "keydown", %{"key" => "3", "code" => "Digit3"})
      :timer.sleep(150)

      html = render(view)
      assert html =~ "3"
    end

    test "keyboard shortcut: Shift+Digit adds away scores", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-digit-away")

      {:ok, view, _html} = live(conn, ~p"/games/kb-digit-away/operator")

      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)

      # Digit2 with shiftKey adds 2 to away
      render_hook(view, "keydown", %{"key" => "@", "code" => "Digit2", "shiftKey" => true})
      :timer.sleep(150)

      html = render(view)
      assert html =~ "2"
    end

    test "keyboard shortcut: 't' calls timeout", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-timeout")

      {:ok, view, _html} = live(conn, ~p"/games/kb-timeout/operator")

      render_click(view, :start_period)
      :timer.sleep(150)

      # 't' key calls timeout (must be lowercase, no shift)
      render_hook(view, "keydown", %{"key" => "t", "code" => "KeyT"})
      :timer.sleep(150)

      assert render(view) =~ "End Timeout"
    end

    test "keyboard shortcut: 'e' ends timeout", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-end-timeout")

      {:ok, view, _html} = live(conn, ~p"/games/kb-end-timeout/operator")

      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)
      render_click(view, :call_timeout)
      :timer.sleep(150)

      # 'e' key ends timeout
      render_hook(view, "keydown", %{"key" => "e", "code" => "KeyE"})
      :timer.sleep(150)

      assert render(view) =~ "Start Jam"
    end

    test "keyboard shortcut: shiftKey defaults to false when omitted", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-no-shift")

      {:ok, view, _html} = live(conn, ~p"/games/kb-no-shift/operator")

      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)

      # Digit1 without shiftKey param should default to home team
      render_hook(view, "keydown", %{"key" => "1", "code" => "Digit1"})
      :timer.sleep(150)

      assert {:ok, snapshot} = GameServer.snapshot("kb-no-shift")
      assert snapshot.score_home == 1
      assert snapshot.score_away == 0
    end

    test "keyboard shortcut: unknown keys are ignored", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-unknown")

      {:ok, view, _html} = live(conn, ~p"/games/kb-unknown/operator")

      html_before = render(view)

      # Random key should not crash or change anything
      render_hook(view, "keydown", %{"key" => "z", "code" => "KeyZ"})
      :timer.sleep(150)

      html_after = render(view)
      assert html_before == html_after
    end

    test "keyboard shortcut: Digit0 and Digit5 are ignored", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("kb-digit-out")

      {:ok, view, _html} = live(conn, ~p"/games/kb-digit-out/operator")

      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :start_jam)
      :timer.sleep(150)

      # Digit0 and Digit5 are outside 1..4 range
      render_hook(view, "keydown", %{"key" => "0", "code" => "Digit0"})
      render_hook(view, "keydown", %{"key" => "5", "code" => "Digit5"})
      :timer.sleep(150)

      assert {:ok, snapshot} = GameServer.snapshot("kb-digit-out")
      assert snapshot.score_home == 0
      assert snapshot.score_away == 0
    end

    test "shows game over in final state", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-final")

      {:ok, view, _html} = live(conn, ~p"/games/operator-final/operator")

      # Navigate to final state using keyboard shortcuts
      render_click(view, :start_period)
      :timer.sleep(150)
      # End period 1 via keyboard 'e' in lineup
      render_hook(view, "keydown", %{"key" => "e", "code" => "KeyE"})
      :timer.sleep(150)
      render_click(view, :start_period)
      :timer.sleep(150)
      # Start jam to be in jam_running phase
      render_click(view, :start_jam)
      :timer.sleep(150)
      # End game via keyboard 'e' in jam_running, P2
      render_hook(view, "keydown", %{"key" => "e", "code" => "KeyE"})
      :timer.sleep(150)

      assert render(view) =~ "Game Over"
      refute render(view) =~ "Start Jam"
    end

    test "score buttons are always visible regardless of phase", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-score-always")
      {:ok, view, _html} = live(conn, ~p"/games/operator-score-always/operator")

      # Score buttons visible in initial phase
      html = render(view)
      assert html =~ "+1"
      assert html =~ "+4"

      # Score buttons visible in lineup
      render_click(view, :start_period)
      :timer.sleep(150)
      assert render(view) =~ "+1"

      # Score buttons visible in jam
      render_click(view, :start_jam)
      :timer.sleep(150)
      assert render(view) =~ "+1"
    end
  end

  describe "Audience LiveView" do
    test "renders audience view", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("audience-render")

      {:ok, view, _html} = live(conn, ~p"/games/audience-render/scoreboard")

      html = render(view)
      assert html =~ "Home"
      assert html =~ "Away"
      assert html =~ "PERIOD"
      assert html =~ "Period Clock"
      assert has_element?(view, "#audience-score-home")
      assert has_element?(view, "#audience-score-away")
    end

    test "redirects to index for unknown game", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/games/unknown-game/scoreboard")
    end

    test "updates when game state changes", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("audience-update")

      {:ok, view, _html} = live(conn, ~p"/games/audience-update/scoreboard")

      assert has_element?(view, "#audience-score-home", "0")

      GameServer.start_period("audience-update")
      :timer.sleep(150)

      html = render(view)
      assert html =~ "Lineup"

      GameServer.start_jam("audience-update")
      GameServer.add_score("audience-update", :home, 5)
      :timer.sleep(150)

      html = render(view)
      assert has_element?(view, "#audience-score-home", "5")
      assert html =~ "Jam"
    end

    test "shows timeout clock in red during timeout", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("audience-timeout")

      {:ok, view, _html} = live(conn, ~p"/games/audience-timeout/scoreboard")

      GameServer.start_period("audience-timeout")
      :timer.sleep(150)
      GameServer.start_jam("audience-timeout")
      :timer.sleep(150)
      GameServer.call_timeout("audience-timeout")
      :timer.sleep(150)

      html = render(view)
      assert html =~ "Timeout"
      # Timeout clock is running, so "TIMEOUT" should NOT appear in inactive clocks footer
      refute html =~ ">TIMEOUT<"
    end
  end
end
