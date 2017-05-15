defmodule Blanket.Mixfile do
  use Mix.Project

  def project do
    [app: :blanket,
     version: "1.0.0",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: "Don't loose your ETS tables with Elixir.",
     package: [
       maintainers: ["Ludovic Demblans"],
       licenses: ["MIT"],
       links: %{
         "GitHub" => "https://github.com/niahoo/blanket",
         "Hex Docs" => "http://hexdocs.pm/blanket",
         "Don't loose your ETS tables" => "http://steve.vinoski.net/blog/2011/03/23/dont-lose-your-ets-tables/",
         "Erlang inspiration" => "https://github.com/DeadZen/etsgive"
       }
     ],
     deps: deps()]
  end

  def application do
    [applications: [:logger],
     mod: {Blanket, []}]
  end

  defp deps do
    [
      {:dogma, "~> 0.1", only: :dev},
      {:earmark, ">= 0.0.0", only: :dev},
      {:ex_doc, "> 0.0.0", only: :dev},
    ]
  end
end
