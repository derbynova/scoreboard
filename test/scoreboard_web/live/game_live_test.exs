defmodule ScoreboardWeb.GameLiveTest do
  use ScoreboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
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
      assert render(view) =~ "0"  # scores are 0
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
      assert render(view) =~ "Timeout"
      assert render(view) =~ "End Period"
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
      assert render(view) =~ "HOME SCORE"
      assert render(view) =~ "AWAY SCORE"

      # 3. Add scores
      render_click(view, :score, %{"team" => "home", "points" => "3"})
      render_click(view, :score, %{"team" => "away", "points" => "2"})
      :timer.sleep(150)
      assert render(view) =~ "3"  # Home score
      assert render(view) =~ "2"  # Away score

      # 4. End jam
      render_click(view, :end_jam)
      :timer.sleep(150)
      assert render(view) =~ "Start Jam"

      # 5. End period 1
      render_click(view, :end_period)
      :timer.sleep(150)
      assert render(view) =~ "Start Period 2"

      # 6. Start period 2
      render_click(view, :start_period)
      :timer.sleep(150)
      assert render(view) =~ "Start Jam"

      # 7. End game
      render_click(view, :end_game)
      :timer.sleep(150)
      assert render(view) =~ "Game Over"
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

    test "shows game over in final state", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("operator-final")

      {:ok, view, _html} = live(conn, ~p"/games/operator-final/operator")

      # Navigate to final state
      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :end_period)
      :timer.sleep(150)
      render_click(view, :start_period)
      :timer.sleep(150)
      render_click(view, :end_game)
      :timer.sleep(150)

      assert render(view) =~ "Game Over"
      refute render(view) =~ "Start Jam"
    end
  end

  describe "Audience LiveView" do
    test "renders audience view", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("audience-render")

      {:ok, view, _html} = live(conn, ~p"/games/audience-render/scoreboard")

      html = render(view)
      assert html =~ "HOME"
      assert html =~ "AWAY"
      assert html =~ "PERIOD"
      assert html =~ "JAM"
    end

    test "redirects to index for unknown game", %{conn: conn} do
      # When game doesn't exist, mount returns a live_redirect
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/games/unknown-game/scoreboard")
    end

    test "updates when game state changes", %{conn: conn} do
      {:ok, _pid} = GameServer.start_game("audience-update")

      {:ok, view, _html} = live(conn, ~p"/games/audience-update/scoreboard")

      # Initial state
      assert render(view) =~ "0"  # Initial scores

      # Start period
      GameServer.start_period("audience-update")
      :timer.sleep(150)

      html = render(view)
      assert html =~ "LINEUP"  # Lineup clock should be shown

      # Start jam and add score
      GameServer.start_jam("audience-update")
      GameServer.add_score("audience-update", :home, 5)
      :timer.sleep(150)

      html = render(view)
      assert html =~ "5"  # Updated home score
      assert html =~ "JAM CLOCK"  # Jam clock should be shown
    end
  end
end
