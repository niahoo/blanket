defmodule MyApp.TableTop do
  use GenServer
  use Blanket

  def start_link(name) do
    # 1. Define a table as you would do with ETS. Here is the equivalent of
    # :ets.new(:users, [:set, :protected])
    table_def = {:users, [:set, :protected]}
    # 2. Create a new Blanket process to be the table heir, passing a name for
    # the table owner process
    {:ok, _} = Blanket.new(__MODULE__, name, table_def)
    # 3. Start your table owner process.
    GenServer.start_link(__MODULE__, [name])
  end

  # ...

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
