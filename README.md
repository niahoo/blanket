# Blanket covers your ETS tables

[![Build Status](https://travis-ci.org/niahoo/blanket.svg?branch=master)](https://travis-ci.org/niahoo/blanket)

If you use ETS with Elixir and Erlang, you know that an ETS table is bound to a process, and that if this process chrashes, the tables vanishes. All data is lost.

The simplest thing to do is to start a process responsible for owning the table, and do all actual table operations on another process. But this requires coodination between the two process, public named tables with an unique name. Sometimes, you need several private or protected unnamed tables.

More informations on theese problems and a simple solution to them can be found on Steve Vinoski's Blog here : [Don't Lose Your ets Tables](http://steve.vinoski.net/blog/2011/03/23/dont-lose-your-ets-tables/).

You can also look et an Erlang implementation of the solution [on github](https://github.com/DeadZen/etsgive).

But all you *need* to from there is to use this package !

## Installation

Just define	the `:blanket` dependency in your project's `mix.exs`.
```elixir
  defp deps do
    [{:blanket, "~> 0.2.0"}]
  end
```

## Documentation

The documentation can be found on [Hex Docs](http://hexdocs.pm/blanket).

## Example

This is a simple example generic table owner server using `Process.register` to register its name. Just check out the comments.

Others strategies for identifying processes are available.

```elixir
defmodule MyApp.TableTop do
  use GenServer
  use Blanket

  def start_link(name) do
    # 1. Define a table as you would do with ETS. Here is the equivalent of
    # :ets.new(:users, [:set, :protected])
    table_def = {:users, [:set, :protected]}
    # 2. Create a new Blanket process to be the table heir, passing a name for
    # the table owner process. The table is created.
    {:ok, _} = Blanket.new(__MODULE__, name, table_def)
    # 3. Start your table owner process.
    GenServer.start_link(__MODULE__, [name])
  end

  # …

  def init([name]) do
    # 1. The table owner registers its name to be found by the table heir. Any
    # registration system is possible, would it be Process.register, or gproc,
    # global, a custom pid store …
    Process.register(self, name)
    # 2. Call Blanket.receive_table to be given the table on fresh start and
    # each time you restart. You must register *before* so the heir can find
    # you.
    {:ok, tab} = Blanket.receive_table
    # 3. You now own the table and can use it
    {:ok, tab}
  end

end

```

## Identifying processes

The previous example uses `Process.register` to register its name. The heir is given the owner's module and its name, and can find the owner's pid by calling `module.get_owner_pid(name)`. This function is defined in your module by calling `use Blanket` in your module definition.

This is equivalent to the following function :

```elixir
  def get_owner_pid(name) do
    Process.whereis(name)
  end
```

If you wish to use a different mechanism, *e.g.* [gproc](https://github.com/uwiger/gproc), you must define your own `get_owner_pid` function :

```elixir
  def get_owner_pid(name) do
    :gproc.whereis({:n, :l, name})
  end
```

You can now register your process with gproc :

```elixir
  def init([name]) do
    :gproc.reg({:n, :l, name})
  end
```

Remember to always register your process before calling Blanket.`receive_table`.

## Options

`Blanket.new` accepts a keyword-list as its fourth argument. At the moment, two keys are accepted :

 - `:transient` — If `true`, the heir will give up on the table when the table owner process exits with `:normal`. Return `{:stop, :normal, state}` from your generic server callbacks and the table will vanish.
 - `:populate` — Must contain an anonymous function. This function will be passed the ETS table as its sole argument and will becalled as the table owner so you can act on private tables. It *must* return `:ok`. Any other value will be returned as an error tuple after the table have been deleted.

```elixir
  opts = [transient: true, populate: fn(tab) -> :ok = do_things(tab) end]
  Blanket.new(module, owner, tab_def, opts)
```

## Transient tables

If you need to shutdown your table owner, you should tell the heir not to wait for a restart by calling `Blanket.abandon_table(tab, heir)`.

You must do this in the table owner process :

```elixir
defmodule MyApp.TemporaryTable do
  use GenServer
  use Blanket

  # …

  def terminate(:normal, {tab, heir}) do
    :ok = Blanket.abandon_table(tab, heir)
  end

  def terminate(error, state) do
    # …
  end

  # …

end
```

This technique has a drawback, you must store the pid of the heir in your generic server state (or somewhere else) in order to turn it off. You can also use the `:transient` option in the heir configuration to achieve this.
