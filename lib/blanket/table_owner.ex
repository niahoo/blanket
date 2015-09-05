defmodule Blanket.TableOwner do

  def default_owner_defs do
    quote location: :keep do

      @doc false
      def get_owner_pid(atom), do: Process.whereis(atom)
      defoverridable [get_owner_pid: 1]

    end
  end

end
