defmodule BlanketTest do
  use ExUnit.Case

  setup do
    :ok = :application.ensure_started(:blanket)
    {:ok, _} = TestTableSup.start_link
    :ok
  end

  test "I can create a table through Blanket" do
    table_name = :test_tab_1
    {:ok, tab} = Blanket.new_table(table_name, [:set], nil)
  end

end


defmodule TestTableSup do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    children = [
      worker(TestTableServer, [])
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end

defmodule TestTableServer do
  use GenServer

  def create(name) do
    Supervisor.start_child(TestTableSup, [name])
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, [name])
  end

  def lookup(name) do
    GenServer.call(name, :lookup)
  end

  # --------------

  def init([name]) do
    Process.register(name)
  end

end
