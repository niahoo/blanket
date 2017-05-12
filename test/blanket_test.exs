defmodule BlanketTest do
  use ExUnit.Case
  # require Logger

  setup do
    # Logger.debug("SETUP ---------------------------------------------")
    :ok = :application.ensure_started(:blanket)
    case Process.whereis(TestTableSup) do
      nil -> :ok
      pid -> Process.exit(pid, :kill)
    end
    {:ok, _} = TestTableSup.start_link
    Process.sleep(600)
    :ok
    # Logger.debug("SETUP OK ------------------------------------------")
  end

  test "Can bootstrap a heir and manage a table a through Blanket" do
    # We will ask blanket for a table. The table will be created
    assert {:ok, tab} = Blanket.claim_table(:some_ref, create_table: __MODULE__)
    # You can't claim the table multiple times (even with the owner process)
    assert {:error, :already_owned} = Blanket.claim_table(:some_ref, create_table: __MODULE__)
    Process.sleep(1000)
  end

  def create_table(opts) do
    {:ok, :ets.new(:test_table_name, [])}
  end

  def create_owner(table_ref) do
    TestTableServer.create(table_ref, [
      register: SomeGlobalPidName,
      create_table: fn() ->
        tab = :ets.new(:public_test_table, [])
        true = :ets.insert(tab, {:counter_key, 0})
        {:ok, tab}
      end,
    ])
  end

  test "A process can be restated and get a table, a heir can also die" do
    # Logger.debug "test process #{__MODULE__} pid = #{inspect self}"
    # Btw, test if we can create with a fun
    assert {:ok, owner} = create_owner(:my_test_table)

    assert 1 = TestTableServer.increment(owner)
    TestTableServer.kill!(owner)
    :timer.sleep(300)

    # owner was killed, the new owner should have been restarted by its
    # supervisor, and the table should have been saved, so the increment
    # continues
    owner = Process.whereis(SomeGlobalPidName)
    assert 2 = TestTableServer.increment(owner)
    TestTableServer.kill!(owner)
    :timer.sleep(300)

    IO.puts "KILLING HEIR"
    [{heir_pid, _}] = Registry.lookup(Blanket.Registry, :my_test_table)
    IO.puts " ---- heir pid : #{inspect heir_pid}"
    Process.exit(heir_pid, :kill)

    # Let the owner get the DOWN message
    :timer.sleep(300)

    # The new increment will do because the owner did not die, so this works :
    owner = Process.whereis(SomeGlobalPidName)
    assert 3 = TestTableServer.increment(owner)
    TestTableServer.kill!(owner)
    :timer.sleep(300)

    # the heir then the owner died, but the table was not lost
    owner = Process.whereis(SomeGlobalPidName)
    assert 4 = TestTableServer.increment(owner)
  end

  test "An owner can abandon the table" do
    IO.puts "@todo abandon table"
  end
end

## -- END OF TESTS

## -- TEST COMPONENTS :


defmodule TestTableSup do
  use Supervisor
  # require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    # Logger.info to_string(__MODULE__ ) <> " starting pid = #{inspect self}"
    Process.register(self(), __MODULE__)
    children = [
      worker(TestTableServer, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end

defmodule TestTableServer do
  use GenServer
  require Logger
  require Record

  defmodule State do
    defstruct [tab: nil, tref: nil]
  end

  def create(tref, opts) do
    Supervisor.start_child(TestTableSup, [tref, opts])
  end

  def start_link(tref, opts) do
    GenServer.start_link(__MODULE__, [tref, opts])
  end

  def kill!(pid) do
    IO.puts "/!\\ Kill process #{inspect pid}"
    Process.exit(pid, :kill)
  end
  def stop!(pid), do: GenServer.call(pid, :stop)

  def increment(pid), do: GenServer.call(pid, :increment)

  def tget(pid, k), do: GenServer.call(pid, {:tget, k})
  def tset(pid, k, v), do: GenServer.call(pid, {:tset, k, v})

  # --------------

  def init(_args=[tref, opts]) do
    claim = Blanket.claim_table(tref, opts ++ [monitor: true, monitor_ref: true])
    Process.register(self(), Keyword.fetch!(opts, :register))
    IO.puts "TestTableServer #{inspect self()} claiming table #{inspect tref} : #{inspect claim}"
    {:ok, tab, _monitor_ref} = claim
    {:ok, %State{tab: tab}}
  end

  def handle_call(:increment, _from, %State{tab: tab}) do
    new_value = :ets.update_counter(tab, :counter_key, 1)
    {:reply, new_value, %State{tab: tab}}
  end

  def handle_call({:tget, k}, _from, %State{tab: tab}) do
    value = case :ets.lookup(tab, k) do
      [] -> nil
      [{^k, v}] -> v
    end
    {:reply, value, %State{tab: tab}}
  end

  def handle_call({:tset, k, v}, _from, %State{tab: tab}) do
    true = :ets.insert(tab, {k, v})
    {:reply, :ok, %State{tab: tab}}
  end

  def handle_call(:stop, _from, %State{tab: tab}) do
    {:stop, :normal, :ok, %State{tab: tab}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %State{tab: tab, tref: tref}) do
    IO.puts "The heir died"
    {:ok, _monitor_ref} = Blanket.recover_heir(tab)
    {:noreply, %State{tab: tab}}
  end

  def handle_info(_info, %State{tab: tab}) do
    IO.puts "~~~~~~ #{__MODULE__} received unhandled info #{inspect _info}"
    {:noreply, %State{tab: tab}}
  end

  def terminate(:normal, %State{tab: tab}) do
    :ok = Blanket.abandon_table(%State{tab: tab})
  end

  def terminate(_, _) do
    # Logger.debug "#{__MODULE__} terminating because=#{inspect error}"
  end

end
