defmodule AdExchange1 do
  use SSPDemo.Bidder
  def handle_call(_req,_,state) do
    {:reply,%SSPDemo.BidResponse{bid: 3},state}
  end
end

defmodule DSP1 do
  use SSPDemo.Bidder
  def handle_call(_req,_,state) do
    {:reply,%SSPDemo.BidResponse{bid: 2},state}
  end
end

defmodule DSP2 do
  use SSPDemo.Bidder
  def handle_call(_req,_,state) do
    {:reply,%SSPDemo.BidResponse{bid: 2},state}
  end
end
