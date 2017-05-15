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
    assert {:error, :already_owned} =
      Blanket.claim_table(:some_ref, create_table: __MODULE__)
    Process.sleep(300)
    assert :ok = Blanket.abandon_table(tab)
  end

  def create_table(_opts) do
    {:ok, :ets.new(:test_table_name, [])}
  end

  def create_owner(table_ref, table_name \\ :test_table, ets_opts \\ []) do
    TestTableServer.create(table_ref, [
      register: SomeGlobalPidName,
      create_table: fn() ->
        tab = :ets.new(table_name, ets_opts)
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

    [{heir_pid, _}] = Registry.lookup(Blanket.Registry, :my_test_table)
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
    tref = make_ref()
    # create a public table
    assert {:ok, owner} =
      create_owner(tref, :public_test_table, [:named_table, :public])
    # it should have a heir
    assert [{heir, _}] = Registry.lookup(Blanket.Registry, tref)
    assert Process.alive?(heir) # dummy test, it should fail later
    assert 1 = TestTableServer.increment(owner)
    assert 2 = TestTableServer.increment(owner)
    # the table is public so we can update it ; this test is quite not usefur
    assert 3 = :ets.update_counter(:public_test_table, :counter_key, 1)
    # still on the same table
    assert 4 = TestTableServer.increment(owner)
    # now stop the process. The gen_server should terminate the heir in
    # terminate/2
    assert :ok = TestTableServer.stop!(owner)
    Process.sleep(300)
    refute Process.alive?(heir) # dummy test, it should fail later
  end
end

# -- END OF TESTS

# -- TEST COMPONENTS :


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
    Process.exit(pid, :kill)
  end
  def stop!(pid), do: GenServer.call(pid, :stop)

  def increment(pid), do: GenServer.call(pid, :increment)

  # --------------

  def init([tref, opts]) do
    opts = opts
    |> Keyword.put(:monitor, true)
    |> Keyword.put(:monitor_ref, true)
    claim = Blanket.claim_table(tref, opts)
    Process.register(self(), Keyword.fetch!(opts, :register))
    {:ok, tab, _monitor_ref} = claim
    {:ok, %State{tab: tab}}
  end

  def handle_call(:increment, _from, %State{tab: tab}) do
    new_value = :ets.update_counter(tab, :counter_key, 1)
    {:reply, new_value, %State{tab: tab}}
  end

  def handle_call(:stop, _from, %State{tab: tab}) do
    {:stop, :normal, :ok, %State{tab: tab}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %State{tab: tab}) do
    {:ok, _monitor_ref} = Blanket.recover_heir(tab)
    {:noreply, %State{tab: tab}}
  end

  def handle_info(_info, %State{tab: tab}) do
    {:noreply, %State{tab: tab}}
  end

  def terminate(:normal, %State{tab: tab}) do
    :ok = Blanket.abandon_table(tab)
  end

  def terminate(_, _) do
    # Logger.debug "#{__MODULE__} terminating because=#{inspect error}"
  end

end
