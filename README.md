# Keep your ETS tables safe and warm with a sweet Blanket.

[![Build Status](https://travis-ci.org/niahoo/blanket.svg?branch=master)](https://travis-ci.org/niahoo/blanket)

If you use ETS with Elixir and Erlang, you know that an ETS table is bound to a process, and that if this process chrashes, the tables vanishes. All data is lost.

The simplest thing to do is to start a process responsible for owning the table, and do all actual table operations on another process. But this requires coodination between the two process, public named tables with an unique name. Sometimes, you need an undefined amount of private or protected unnamed tables.

More informations on theese problems and a simple solution to them can be found on Steve Vinoski's Blog here : [Don't Lose Your ets Tables](http://steve.vinoski.net/blog/2011/03/23/dont-lose-your-ets-tables/).

You can also look at an Erlang implementation of the solution [on github](https://github.com/DeadZen/etsgive).

Or you can go the simple way and use Blanket.

## Installation

Just define	the `:blanket` dependency in your project's `mix.exs` and require the application to be started.

```elixir
  defp deps do
    [{:blanket, "~> 0.3.1"}]
  end

  def application do
    [mod: {MyApp, []},
     applications: [:blanket]]
  end
```

## Documentation

The documentation can be found on [Hex Docs](https://hexdocs.pm/blanket/Blanket.html).

## Example

```elixir
defmodule MyApp.TableOwner do
  use GenServer

  def create(table_ref) do
    # 1. Create your process with the table reference being part of the child
    # spec, so your process can be restarted with the same reference.
    # Table reference is not a table identifier returned by :ets.new but
    child_spec = Supervisor.Spec.worker(__MODULE__,[table_ref])
    Supervisor.start_child(MyApp.Supervisor, child_spec)
  end

  def start_link(table_ref) do
    GenServer.start_link(__MODULE__, [table_ref])
  end

  # 2. Create the table on the server side. If your process crashes, the table
  # will be protected by a heir, and if you claim the table again with the same
  # reference, the existing table will be returned.
  def init([table_ref]) do
    {:ok, tab} = Blanket.claim_table(tref, create_table: fn() ->
      tab = :ets.new(:my_tab)
      {:ok, tab}
    end)
    {:ok, %State{tab: tab}}
  end

  # 3. If you want to use temporary tables, just tell Blanket to forget about
  # the table before terminating your process.
  def terminate(:normal, %State{tab: tab}) do
    :ok = Blanket.abandon_table(tab)
  end
  def terminate(reason, state) do
    # handle other failures
  end

end

```