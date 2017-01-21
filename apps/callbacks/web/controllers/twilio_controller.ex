defmodule Callbacks.TwilioController do
  use Callbacks.Web, :controller

  defmacro call_failed_to_connect(call_status) do
    quote do: unquote(call_status) in ~w(busy canceled failed no-answer)
  end

  defmacro call_completed(call_status) do
    quote do: unquote(call_status) in ~w(completed)
  end

  defmacro call_progressing(call_status) do
    quote do: unquote(call_status) in ~w(queued ringing in-progress)
  end

  def chair_answered(conn, %{"conference" => conference, "chair" => chair, "conference_status_callback" => conference_status_callback}) do
    Events.publish(%Events.ChairJoiningConference{conference: conference, chair: chair})
    conn
    |> put_resp_content_type("text/xml")
    |> text(Callbacks.Twiml.join_conference(conference, conference_status_callback))
  end

  def chair_call_status_changed(conn, %{"conference" => conference, "chair" => chair, "CallStatus" => call_status}) when call_failed_to_connect(call_status) do
    Events.publish(%Events.ChairFailedToJoinConference{conference: conference, chair: chair, reason: call_status})
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  def chair_call_status_changed(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  def pending_participant_answered(conn, %{"conference" => conference, "chair" => chair, "pending_participant" => pending_participant}) do
    # TODO: probably do not need this event - Events.publish(%Events.PendingParticipantJoiningConference{conference: conference, chair: chair, pending_participant: pending_participant})
    conn
    |> put_resp_content_type("text/xml")
    |> text(Callbacks.Twiml.join_conference(conference))
  end

  def participant_call_status_changed(conn, %{"conference" => conference, "chair" => chair, "participant" => pending_participant, "CallStatus" => call_status}) when call_progressing(call_status) do
    Events.publish(%Events.PendingParticipantCallStatusChanged{conference: conference, chair: chair, pending_participant: pending_participant, call_status: call_status})
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  def participant_call_status_changed(conn, %{"conference" => conference, "chair" => chair, "participant" => pending_participant, "CallStatus" => call_status}) when call_failed_to_connect(call_status) do
    Events.publish(%Events.PendingParticipantFailedToJoinConference{conference: conference, chair: chair, pending_participant: pending_participant, reason: call_status})
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  def participant_call_status_changed(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end

  # TODO: move into separate conferences module
  def conference_status_changed(conn, %{"conference" => conference, "chair" => chair, "StatusCallbackEvent" => event}) do
    # TODO #Events.publish(%Events.ChairFailedToJoinConference{conference: conference, chair: chair, reason: call_status})
    conn
    |> put_resp_content_type("text/xml")
    |> text("ok")
  end
end
