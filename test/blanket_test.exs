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
    :ok
    :timer.sleep(600)
    # Logger.debug("SETUP OK ------------------------------------------")
  end

  test "Can bosttrap a heir and manage a table a through Blanket" do
    tab_def = {:test_tab_1, [:set, :private]}
    owner = :table_owner_name
    Process.register(self, owner)
    assert {:ok, heir_pid} = Blanket.new(__MODULE__, owner, tab_def)
    assert is_pid(heir_pid)
    assert {:ok, _} = Blanket.receive_table(2000)
  end

  test "A process can be restated and get a table" do
    # Logger.debug "test process #{__MODULE__} pid = #{inspect self}"
    tab_def = {:test_tab_2, [:set, :private]}
    owner = :some_gen_server_name
    init_counter = fn(tab) ->
      true = :ets.insert(tab, {:counter_key, 0})
      :ok
    end
    assert {:ok, _} = Blanket.new(TestTableServer, owner, tab_def, init_counter)
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
    # Logger.debug "test process #{__MODULE__} pid = #{inspect self}"
    tab_def = {:test_tab_3, [:set, :private]}
    owner = :a_kv_store
    populate = fn(tab) ->
      :ets.insert(tab, {:hero, {"Sonic", :hedgehog}})
      :ok
    end
    assert {:ok, _} = Blanket.new(TestTableServer, owner, tab_def, populate)
    assert {:ok, _} = TestTableServer.create(owner)
    assert {"Sonic", :hedgehog} = TestTableServer.tget(owner, :hero)

    TestTableServer.kill!(owner)
    :timer.sleep(300)

    assert {"Sonic", :hedgehog} = TestTableServer.tget(owner, :hero)
    assert nil === TestTableServer.tget(owner, :villain)
    assert :ok === TestTableServer.tset(owner, :villain, {"Robotnik", :doctor})
    assert {"Robotnik", :doctor} = TestTableServer.tget(owner, :villain)

    TestTableServer.kill!(owner)
    :timer.sleep(300)

    assert {"Sonic", :hedgehog} = TestTableServer.tget(owner, :hero)
    assert {"Robotnik", :doctor} = TestTableServer.tget(owner, :villain)
  end

  test "Acting on table must return ok" do
    tab_def = {:test_tab_4, [:set, :private]}
    populate = fn(_) -> :fail end
    assert {:error, :fail} = Blanket.new(__MODULE__, :me, tab_def, populate)
  end

  test "Acting on table errors are not rewraped if already like {:error, _}" do
    tab_def = {:test_tab_4, [:set, :private]}
    populate = fn(_) -> {:error, :reason} end
    assert {:error, :reason} = Blanket.new(__MODULE__, :me, tab_def, populate)
  end

  test "The heir gives up the table if abandon_table is called" do
    public_name = :test_tab_5
    tab_def = {public_name, [:set, :public, :named_table]}
    owner = :gen_server_that_stops
    check_table_exists = fn(tab) ->
      try do
        true = :ets.insert(tab, {:tab_control, "some value"})
      rescue
        _e in ArgumentError -> false
      end
    end
    # the table exists after blanket has been started
    assert {:ok, heir} = Blanket.new(__MODULE__, owner, tab_def)
    assert check_table_exists.(public_name)
    # the table exists after the server has been started
    TestTableServer.create(owner, heir)
    assert check_table_exists.(public_name)
    # the table exists after the server has been killed
    TestTableServer.kill!(owner)
    assert check_table_exists.(public_name)
    :timer.sleep(300)
    assert check_table_exists.(public_name)
    # The heir is alive
    assert Process.alive?(heir)
    # the table does not exists after the server has been stopped.
    owner_pid = TestTableServer.get_owner_pid(owner)
    Process.monitor(owner_pid)
    assert :ok === TestTableServer.stop!(owner)
    receive do
      {:'DOWN', _, _, _, :normal} -> :ok
    after
      1000 -> assert false
    end
    assert not check_table_exists.(public_name)
    # ... and the owner and the heir are gone
    assert not Process.alive?(heir)
    assert not Process.alive?(owner_pid)
  end

  def get_owner_pid(atom), do: Process.whereis(atom)


end

defmodule BlanketTest.Macros do
  use ExUnit.Case
  use Blanket
  # require Logger

  test "Blanket.__using__ defines a default get_owner_pid()" do
    # the function is a simple call for Process.whereis
    proc_name = :test_macro_proc_name
    assert nil = get_owner_pid(proc_name)
    aaa = self
    pid = spawn(fn() ->
      Process.register(self, proc_name)
      # Logger.debug "Tiny proc started"
      send(aaa, :ack)
      receive do
        :stop ->
            # Logger.debug "Stopped !"
            :ok
      end
    end)
    receive do
      :ack -> :ok
    end
    # Logger.debug "tiny pid is = #{inspect pid}"
    assert ^pid = get_owner_pid(proc_name)
    assert Process.whereis(proc_name) === get_owner_pid(proc_name)
    assert ^pid = get_owner_pid(proc_name)
    send(pid, :stop)
  end
end

defmodule BlanketTest.Macros2 do
  use ExUnit.Case
  use Blanket

  test "Blanket.__using__ imports are overridable" do
    assert {:other, :thing} = get_owner_pid(:thing)
  end


  def get_owner_pid(x), do: {:other, x}
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
    Process.register(self, __MODULE__)
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
  Record.defrecord :state, tab: nil, heir: nil

  def create(name, heir \\ nil) do
    Supervisor.start_child(TestTableSup, [name, heir])
  end

  def start_link(name, heir) do
    GenServer.start_link(__MODULE__, [name, heir])
  end

  def kill!(name), do: Process.exit(get_owner_pid(name), :kill)
  def stop!(name), do: GenServer.call(name, :stop)

  def increment(name), do: GenServer.call(name, :increment)

  def tget(name, k), do: GenServer.call(name, {:tget, k})
  def tset(name, k, v), do: GenServer.call(name, {:tset, k, v})

  def get_owner_pid(atom), do: Process.whereis(atom)

  # --------------

  # the state is just the table ID

  def init(_args=[name, heir]) do
    Process.register(self, name)
    # Logger.debug "#{__MODULE__} starting, args = #{inspect _args}"
    {:ok, tab} = Blanket.receive_table
    {:ok, state(tab: tab, heir: heir)}
  end

  def handle_call(:increment, _from, s=state(tab: tab)) do
    new_value = :ets.update_counter(tab, :counter_key, 1)
    {:reply, new_value, s}
  end

  def handle_call({:tget, k}, _from, s=state(tab: tab)) do
    value = case :ets.lookup(tab, k) do
      [] -> nil
      [{^k, v}] -> v
    end
    {:reply, value, s}
  end

  def handle_call({:tset, k, v}, _from, s=state(tab: tab)) do
    true = :ets.insert(tab, {k, v})
    {:reply, :ok, s}
  end

  def handle_call(:stop, _from, s=state(tab: tab, heir: heir)) do
    :ok = Blanket.abandon_table(tab, heir)
    {:stop, :normal, :ok, s}
  end

  # def handle_info(_info, tab) do
  #   # Logger.debug "#{__MODULE__} received unhandled info #{inspect info}"
  #   {:noreply, s}
  # end

end
