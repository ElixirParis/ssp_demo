defmodule AdExchange1 do
  use SSPDemo.Bidder
  def handle_call(_req,_,state) do
    {:reply,%SSPDemo.BidResponse{bid: 3},state}
  end
end

defmodule DSP2 do
  use SSPDemo.Bidder
  def handle_call(_req,_,state) do
    {:reply,%SSPDemo.BidResponse{bid: 2},state}
  end
end

defmodule OpenBidder do
  use SSPDemo.Bidder
  def start_link(_) do
    dir = "#{:code.priv_dir(:ssp_demo)}/open_bidder"
    Exos.Proc.start_link("java -cp target/open-bidder-0.0.1-standalone.jar clojure.main open_bidder.clj",nil, cd: dir)
  end
  # todo map agencies with agency/1, construct open bidder request
  def map_request(req), do: req
  def map_response(%{bid: bid}), do: %SSPDemo.BidResponse{bid: bid}

  for line<-File.stream!("google_spec/agencies"), [id,name]=String.split(line," ", parts: 2) do
    def agency(unquote(String.rstrip(name,?\n))), do: unquote(String.to_integer(id))
  end
  def agency(_), do: 0

  defmodule Elixir.Mix.Tasks.UpdateGoogleSpec do
    use Mix.Task

    def run(_) do
      :inets.start
      case :httpc.request('https://storage.googleapis.com/adx-rtb-dictionaries/agencies.txt?hl=fr') do
        {:ok,{{_,200,_},_,body}}->
          File.write!("google_spec/agencies",body)
          Mix.shell.info "successfully update google spec files"
        _->
          Mix.shell.info "failed to update google spec files, cannot access google url"
      end
    end
  end
end
