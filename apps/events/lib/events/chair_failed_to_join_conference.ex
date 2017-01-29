defmodule Events.ChairFailedToJoinConference do
  @moduledoc """
  Documentation for Events.
  """
  @derive [Poison.Encoder]
  @enforce_keys [:conference, :chair, :call_sid, :reason]
  defstruct [
    conference: nil,
    chair: nil,
    call_sid: nil,
    reason: nil
  ]

  @type t :: %__MODULE__{
    conference: String.t,
    chair: String.t,
    call_sid: String.t,
    reason: String.t
  }
end
