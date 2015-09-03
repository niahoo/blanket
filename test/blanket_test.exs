defmodule BlanketTest do
  use ExUnit.Case
  alias Blanket.Heir
  require Logger

  setup do
    Logger.debug("SETUP ---------------------------------------------")
    :ok = :application.ensure_started(:blanket)
    case Process.whereis(TestTableSup) do
      nil -> :ok
      pid -> Process.exit(pid, :kill)
    end
    {:ok, _} = TestTableSup.start_link
    :ok
    :timer.sleep(600)
    Logger.debug("SETUP OK ------------------------------------------")
  end

  test "Can bosttrap a heir and manage a table a through Blanket" do
    tab_def = {:test_tab_1, [:set, :private]}
    owner = :table_owner_name
    Process.register(self, owner)
    assert :ok = Heir.new(__MODULE__, owner, tab_def)
    assert {:ok, tab} = Heir.receive_table(2000)
  end

  test "A process can be restated and get a table" do
    Logger.debug "test process #{__MODULE__} pid = #{inspect self}"
    tab_def = {:test_tab_2, [:set, :private]}
    owner = :some_gen_server_name
    assert :ok = Heir.new(TestTableServer, owner, tab_def)
    assert {:ok, _} = TestTableServer.create(owner)
    assert 1 = TestTableServer.increment(owner)
    TestTableServer.kill!(owner)
    :timer.sleep(300)
    assert 2 = TestTableServer.increment(owner)
    TestTableServer.kill!(owner)
    :timer.sleep(300)
    assert 3 = TestTableServer.increment(owner)
    TestTableServer.kill!(owner)
    :timer.sleep(300)
    assert 4 = TestTableServer.increment(owner)
  end

  test "It is possible to act on the table at startup" do
    Logger.debug "test process #{__MODULE__} pid = #{inspect self}"
    tab_def = {:test_tab_3, [:set, :private]}
    owner = :a_kv_store
    populate = fn(tab) ->
      :ets.insert(tab, {:hero, {"Sonic", :hedgehog}})
      :ok
    end
    assert :ok = Heir.new(TestTableServer, owner, tab_def, populate)
    assert {:ok, _} = TestTableServer.create(owner)
    assert {"Sonic", :hedgehog} = TestTableServer.tget(owner, :hero)

    TestTableServer.kill!(owner)
    :timer.sleep(300)

    assert {"Sonic", :hedgehog} = TestTableServer.tget(owner, :hero)
    assert nil = TestTableServer.tget(owner, :villain)
    assert :ok = TestTableServer.tset(owner, :villain, {"Robotnik", :doctor})
    assert {"Robotnik", :doctor} = TestTableServer.tget(owner, :villain)

    TestTableServer.kill!(owner)
    :timer.sleep(300)

    assert {"Sonic", :hedgehog} = TestTableServer.tget(owner, :hero)
    assert {"Robotnik", :doctor} = TestTableServer.tget(owner, :villain)
  end

  test "Acting on table must return ok" do
    tab_def = {:test_tab_4, [:set, :private]}
    populate = fn(_) -> :fail end
    assert {:error, :fail} = Heir.new(__MODULE__, :me, tab_def, populate)
  end

  test "Acting on table errors are not rewraped if already like {:error, _}" do
    tab_def = {:test_tab_4, [:set, :private]}
    populate = fn(_) -> {:error, :reason} end
    assert {:error, :reason} = Heir.new(__MODULE__, :me, tab_def, populate)
  end

  def get_owner_pid(atom), do: Process.whereis(atom)

end


defmodule TestTableSup do
  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    Logger.info to_string(__MODULE__ ) <> " starting pid = #{inspect self}"
    Process.register(self, __MODULE__)
    children = [
      worker(TestTableServer, [])
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end

defmodule TestTableServer do
  use GenServer
  require Logger

  def create(name) do
    Supervisor.start_child(TestTableSup, [name])
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, [name])
  end

  def kill!(name), do: Process.exit(get_owner_pid(name), :kill)

  def increment(name), do: GenServer.call(name, :increment)

  def tget(name, k), do: GenServer.call(name, {:tget, k})
  def tset(name, k, v), do: GenServer.call(name, {:tset, k, v})

  def get_owner_pid(atom), do: Process.whereis(atom)

  # --------------

  # the state is just the table ID

  def init([name]) do
    Process.register(self, name)
    Logger.debug "#{__MODULE__} starting, pid = #{inspect self}"
    {:ok, tab} = Blanket.Heir.receive_table
    {:ok, tab}
  end


  def handle_call(:increment, _from, tab) do
    # @todo remove loggin here
    new_value = :ets.update_counter(tab, :counter_key, 1, {:_, 0})
    {:reply, new_value, tab}
  end

  def handle_call({:tget, k}, _from, tab) do
    # @todo remove loggin here
    value = case :ets.lookup(tab, k) do
      [] -> nil
      [{^k, v}] -> v
    end
    {:reply, value, tab}
  end

  def handle_call({:tset, k, v}, _from, tab) do
    # @todo remove loggin here
    true = :ets.insert(tab, {k, v})
    {:reply, :ok, tab}
  end

  def handle_info(info, tab) do
    # @todo remove loggin here
    Logger.debug "#{__MODULE__} received unhandled info #{inspect info}"
    {:noreply, tab}
  end

end
