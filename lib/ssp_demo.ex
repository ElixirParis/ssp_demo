defmodule SSPDemo.App do
  use Application
  import Supervisor.Spec

  def start(_,_) do
    Supervisor.start_link([
      supervisor(SSPDemo.App.BidderCallerSup,[],[]),
      worker(SSPDemo.Reporter,[],[]),
      Plug.Adapters.Cowboy.child_spec(:http,SSPDemo.HTTP,[], port: 9888)
    ], strategy: :one_for_one)
  end

  defmodule BidderCallerSup do
    import Supervisor.Spec
    def start_link do
      Supervisor.start_link([
        worker(SSPDemo.Config,[],[]),
        supervisor(SSPDemo.App.BidderSup,[],[]),
        supervisor(SSPDemo.CallerSup,[],[])
      ] , strategy: :one_for_one)
    end
  end

  defmodule BidderSup do
    import Supervisor.Spec
    def start_link do
      bidders = Application.get_env(:ssp_demo,:bidders)
      Supervisor.start_link(for %{name: name}=bidder<-bidders do
        worker(SSPDemo.Throttler,[bidder],id: name)
      end, strategy: :one_for_one)
    end
  end
end

defmodule SSPDemo.Throttler do
  use GenServer

  defmodule TimeRing do
    defstruct set: {}, oldest_idx: 0, m: 5, n: 1
    def now, do: :erlang.system_time(:milli_seconds)
    def new(m,n),do: %TimeRing{set: :erlang.make_tuple(m,now),m: m, n: n, oldest_idx: 0}
    def next(%{set: s,oldest_idx: idx,n: n, m: m}=ring) do
      wait = max(0,n - (now - elem(s,idx)))
      ring = %{ring| set: put_elem(s,idx,now+wait), oldest_idx: if(idx+1>m-1, do: 0, else: idx+1)}
      {wait,ring}
    end
  end

  def start_link(bidder), do:
    GenServer.start_link(__MODULE__, bidder, name: bidder.name)

  def init(%{mod: mod,conf: conf,nb_per_ms: {m,n}, max_q: maxqlen}) do
    {:ok,pid} = mod.start_link(conf)
    {:ok,%{pid: pid, tr: TimeRing.new(m,n), maxqlen: maxqlen, qlen: 0, q: :queue.new}}
  end
  def handle_call(_req,_reply_to,%{maxqlen: qlen, qlen: qlen}=state) do
    {:reply,:dropped,state}
  end
  def handle_call(req,reply_to,%{q: q,tr: timering, qlen: qlen}=state) do
    {wait,timering} = TimeRing.next(timering)
    if wait > 1000 do
      {:reply,:dropped,state}
    else
      Process.send_after(self,:timeout,wait)
      {:noreply,%{state| qlen: qlen+1, q: :queue.in({req,reply_to},q), tr: timering}}
    end
  end
  def handle_info(:timeout,%{pid: pid, q: q, qlen: qlen}=state) do
    {:registered_name,bidder} = Process.info(self,:registered_name)
    {{:value, {req,reply_to}}, q} = :queue.out(q)
    spawn(fn-> 
      res = GenServer.call(pid,req)
      GenServer.reply(reply_to,res) 
      Riemann.send_async([%{service: "bid", metric: res.bid,attributes: [bidder: bidder]}])
    end)
    {:noreply,%{state|q: q, qlen: qlen-1}}
  end
end

defmodule SSPDemo.Bidder do
  use Behaviour 
  defcallback start_link(conf::any)
  defcallback map_request(SSPDemo.BidRequest.t) :: any
  defcallback use_bidder(SSPDemo.BidRequest.t) :: boolean

  defmacro __using__(_opts) do
    quote do
      @behaviour SSPDemo.Bidder
      use GenServer
      def start_link(conf) do
        GenServer.start_link(__MODULE__,conf,[])
      end
      def map_request(req), do: req
      def use_bidder(req), do: true

      defoverridable [start_link: 1, map_request: 1, use_bidder: 1]
    end
  end
end

defmodule SSPDemo.BidRequest do
  defstruct ip: nil, user_agent: nil, language: "en", verticals: [], geo: nil,  
            min_cpm: 0, excluded_agencies: [], excluded_rich_media: [],
            width: 0, height: 0, params: []
end

defmodule SSPDemo.BidResponse do
  defstruct bid: 0, html: ""
end

defmodule SSPDemo.Config do
  def start_link, do:
    Agent.start_link(fn -> Application.get_env(:ssp_demo,:bid_config) end, name: __MODULE__)
  def update(conf), do: Agent.update(__MODULE__, fn _->conf end)
  def get, do: Agent.get(__MODULE__, &(&1))
end

defmodule SSPDemo.CallerSup do
  def start_link, do: 
    Task.Supervisor.start_link(name: __MODULE__, restart: :transient)
  def request(bidder_id,bidrequest) do
    Task.Supervisor.async(__MODULE__, fn ->
      GenServer.call(bidder_id,bidrequest)
    end)
  end
end

defmodule SSPDemo.Reporter do
  use GenServer
  def start_link, do:
    GenServer.start_link(__MODULE__,[], name: __MODULE__) 

  def handle_cast(res,state) do
    Riemann.send_async([%{service: "auction_response", metric: res && res.bid || -1}])
    {:noreply,state}
  end
end

defmodule SSPDemo do
  def auction(ip,user_agent,language,slot_id) do
    conf = SSPDemo.Config.get
    min_cpm = conf.min_cpm
    request = bidrequest(ip,user_agent,language,slot_id,conf)
    response = Application.get_env(:ssp_demo,:bidders)
      |> Enum.filter(& &1.mod.use_bidder(request))
      |> Enum.map(&SSPDemo.CallerSup.request(&1.name,request))
      |> Enum.map(&Task.yield(&1,1000))
      |> Enum.reject(fn nil->true # query time is too long
                        {:ok,:dropped}->true # throttler queue is overloaded
                        {:ok,%{bid: bid}} when bid<min_cpm->true # bid is too low
                        _->false 
                      end)
      |> Enum.map(fn {:ok,resp}->resp end)
      |> Enum.sort_by(& &1.bid)
      |> List.last
    GenServer.cast SSPDemo.Reporter, response
    response
  end
  defp bidrequest(ip,user_agent,language,slot_id,conf) do
    struct(SSPDemo.BidRequest,
      [ip: ip, user_agent: user_agent, language: language]
      |> Dict.merge(Dict.delete(conf,:slots))
      |> Dict.merge(conf.slots[slot_id] || []))
  end
end

defmodule SSPDemo.HTTP do
  use Plug.Router
  plug :match
  plug :dispatch

  get "/ad/:slot" do
    ua = get_req_header(conn,"user-agent") |> List.first |> to_string
    response = SSPDemo.auction(conn.remote_ip,ua,"fr",slot)
    conn |> put_resp_content_type("application/json")
         |> send_resp(200, Poison.encode!(response))
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
