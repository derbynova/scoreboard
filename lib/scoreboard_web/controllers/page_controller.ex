defmodule ScoreboardWeb.PageController do
  use ScoreboardWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
