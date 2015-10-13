defmodule Mix.Tasks.Compile.Openbidder do
  @shortdoc "Create open_bidder Jar"
  def run(_) do
    if not File.exists?("priv/open_bidder/target/open-bidder-0.0.1-standalone.jar") do
      System.cmd "lein", ["uberjar"], cd: "priv/open_bidder", into: IO.stream(:stdio,:line)
    end
  end
end

defmodule SSPDemo.Mixfile do
  use Mix.Project

  def project do
    [app: :ssp_demo,
     version: "0.0.1",
     elixir: "~> 1.1",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     compilers: [:openbidder] ++ Mix.compilers,
     deps: deps]
  end

  def application do
    [applications: [:logger,:plug,:cowboy,:iex,:poison, :exos,:riemann],
     mod: {SSPDemo.App,[]}]
  end

  defp deps do
    [{:cowboy, "~> 1.0"},
     {:plug, "~> 1.0"},
     {:exos, "~> 1.0.0"},
     {:poison, "~> 1.5.0"},
     {:riemann, " ~> 0.0.11"}]
  end
end
