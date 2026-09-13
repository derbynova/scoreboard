# DerbyNova Scoreboard

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Match actions are saved in SQLite. After a restart, reopen the match's operator
URL to recover it with clocks paused for confirmation. See
[match recovery](docs/match-recovery.md) for guarantees, limitations and migration instructions.

For clock behavior, end-of-period confirmation and upgrade compatibility, see
[match clocks](docs/clock-cycle.md).

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
