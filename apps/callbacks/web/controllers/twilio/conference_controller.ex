defmodule Callbacks.Twilio.ConferenceController do
  @moduledoc """
  This controller is responsible for responding to requests from Twilio
  regarding the status of conferences.
  """
  use Callbacks.Web, :controller

  defmacrop participant_joined(event) do
    quote do: unquote(event) in ~w(participant-join)
  end

  defmacrop participant_left(event) do
    quote do: unquote(event) in ~w(participant-leave)
  end

  defmacrop conference_ended(event) do
    quote do: unquote(event) in ~w(conference-end)
  end

  @doc """
  Called when Twilio informs us that the status of the conference has changed.
  In the case that a participant has joined the conference, we publish an event
  indicating so.
  """
  def status_changed(conn, %{"conference" => conference, "chair" => chair, "ConferenceSid" => conference_sid, "CallSid" => call_sid, "StatusCallbackEvent" => event}) when participant_joined(event) do
    {:ok, _} = Events.publish(%Events.ParticipantJoinedConference{conference: conference, chair: chair, call_sid: call_sid, conference_sid: conference_sid})
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  @doc """
  Called when Twilio informs us that the status of the conference has changed.
  In the case that a participant has left the conference, we publish an event
  indicating so.
  """
  def status_changed(conn, %{"conference" => conference, "chair" => chair, "ConferenceSid" => conference_sid, "CallSid" => call_sid, "StatusCallbackEvent" => event}) when participant_left(event) do
    {:ok, _} = Events.publish(%Events.ParticipantLeftConference{conference: conference, chair: chair, call_sid: call_sid, conference_sid: conference_sid})
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  @doc """
  Called when Twilio informs us that the status of the conference has changed.
  In the case that the conference has ended, we publish an event indicating so.
  """
  def status_changed(conn, %{"conference" => conference, "chair" => chair, "ConferenceSid" => conference_sid, "StatusCallbackEvent" => event}) when conference_ended(event) do
    {:ok, _} = Events.publish(%Events.ConferenceEnded{conference: conference, chair: chair, conference_sid: conference_sid})
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  @doc """
  Called when Twilio informs us that the status of the conference has changed.
  This is the catch-call case which will simply respond 'ok' and has no side effects.
  Necessary because we do not care about all of the conference statuses.
  """
  def status_changed(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end
end
