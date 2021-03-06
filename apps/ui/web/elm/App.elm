module App exposing (..)

import Html exposing (..)
import Html.Attributes exposing (class)

import Json.Decode as JsDecode
import Json.Encode as JsEncode

import Phoenix.Socket
import Phoenix.Channel
import Phoenix.Push

import Twilio

import Line

import Conference


main =
  Html.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


-- MODEL

type alias Flags =
  { clientName : String
  }


type alias Model =
  { phxSocket : Phoenix.Socket.Socket Msg
  , status : String
  , clientName : String
  , twilioStatus : String
  , line : Line.Model
  , conference : Maybe Conference.Model
  , conferenceStatus : String
  }


clientsChannel : String -> String
clientsChannel clientName =
    "twilio:" ++ clientName


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        channel =
            Phoenix.Channel.init (clientsChannel flags.clientName)

        ( initSocket, phxCmd ) =
            Phoenix.Socket.init "ws://localhost:5000/socket/websocket"
                |> Phoenix.Socket.withDebug
                |> Phoenix.Socket.on "conference_changed" (clientsChannel flags.clientName) ConferenceChanged
                |> Phoenix.Socket.on "set_token" (clientsChannel flags.clientName) SetupTwilio
                |> Phoenix.Socket.join channel

        model =
            { phxSocket = initSocket
            , status = "All good"
            , clientName = flags.clientName
            , twilioStatus = "All good"
            , line = ""
            , conference = Nothing
            , conferenceStatus = "All good"
            }
    in
        ( model, Cmd.map PhoenixMsg phxCmd )


-- UPDATE

type Msg
    = PhoenixMsg (Phoenix.Socket.Msg Msg)
    | ConferenceChanged JsEncode.Value
    | RequestFailed JsEncode.Value
    | RequestSubmitted JsEncode.Value
    | TwilioStatusChanged String
    | SetupTwilio JsEncode.Value
    | LineMsg Line.Msg
    | ConferenceMsg Conference.Msg

sendRequest : Model -> String -> JsDecode.Value -> ( Phoenix.Socket.Socket Msg, Cmd (Phoenix.Socket.Msg Msg) )
sendRequest model requestName payload =
    let
        phxPush =
            Phoenix.Push.init requestName (clientsChannel model.clientName)
                |> Phoenix.Push.withPayload payload
                |> Phoenix.Push.onOk RequestSubmitted
                |> Phoenix.Push.onError RequestFailed

        ( phxSocket, phxCmd ) =
            Phoenix.Socket.push phxPush model.phxSocket
    in
        ( phxSocket, phxCmd )

sendStartCall : Model -> Line.Callee -> ( Phoenix.Socket.Socket Msg, Cmd (Phoenix.Socket.Msg Msg) )
sendStartCall model callee =
    sendRequest model "start_call" (encodedCall callee model.clientName)


sendRequestToCancelPendingParticipant : Model -> Conference.Model -> Conference.CallLeg -> ( Phoenix.Socket.Socket Msg, Cmd (Phoenix.Socket.Msg Msg) )
sendRequestToCancelPendingParticipant model conference callLeg =
    sendRequest model "request_to_cancel_pending_participant" (encodedPendingParticipantReference conference callLeg)


sendRequestToHangupParticipant : Model -> Conference.Model -> Conference.CallLeg -> ( Phoenix.Socket.Socket Msg, Cmd (Phoenix.Socket.Msg Msg) )
sendRequestToHangupParticipant model conference callLeg =
    sendRequest model "request_to_hangup_participant" (encodedParticipantReference conference callLeg)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TwilioStatusChanged twilioStatus ->
            ( { model | twilioStatus = twilioStatus }
            , Cmd.none
            )

        SetupTwilio raw ->
            let
                decodeResult =
                    JsDecode.decodeValue decodeTwilioToken raw
            in
                case decodeResult of
                    Ok token ->
                        ( { model | status = "Twilio token received" }
                        , Twilio.setup token
                        )

                    Err error ->
                        ( { model | status = error }
                        , Cmd.none
                        )

        ConferenceChanged raw ->
            let
                decodeResult =
                    JsDecode.decodeValue Conference.decodeResponse raw
            in
                case decodeResult of
                    Ok response ->
                        ( { model
                              | conference = response.conference
                              , conferenceStatus = response.message
                          }
                        , Cmd.none
                        )

                    Err error ->
                        ( { model | status = error }
                        , Cmd.none
                        )

        RequestFailed raw ->
            let
                decodeResult =
                    JsDecode.decodeValue decodeCallRequestFailure raw
            in
                case decodeResult of
                    Ok message ->
                        ( { model | status = "Request failed with error: " ++ message }
                        , Cmd.none
                        )

                    Err error ->
                        ( { model | status = "Failed to decode call request failure: " ++ error }
                        , Cmd.none
                        )

        RequestSubmitted raw ->
            ( { model | status = "Request submitted" }
            , Cmd.none
            )

        LineMsg subMsg ->
            let
                ( updatedLineModel, lineCmd ) =
                    Line.update subMsg model.line

                ( phxSocket, phxCmd ) =
                    case subMsg of
                        Line.RequestCall ->
                            sendStartCall model model.line

                        _ ->
                            ( model.phxSocket, Cmd.none )
            in
                ( { model
                      | line = updatedLineModel
                      , phxSocket = phxSocket
                  }
                , Cmd.batch [ Cmd.map LineMsg lineCmd
                            , Cmd.map PhoenixMsg phxCmd
                            ]
                )

        ConferenceMsg subMsg ->
            case model.conference of
                Nothing ->
                    ( model, Cmd.none )

                Just conference ->
                    let
                        ( updatedConferenceModel, conferenceCmd ) =
                            Conference.update subMsg conference

                        ( phxSocket, phxCmd ) =
                            case subMsg of
                                (Conference.Cancel callLeg) ->
                                    sendRequestToCancelPendingParticipant model updatedConferenceModel callLeg

                                (Conference.Hangup callLeg) ->
                                    sendRequestToHangupParticipant model updatedConferenceModel callLeg
                    in
                        ( { model
                              | conference = Just updatedConferenceModel
                              , phxSocket = phxSocket
                          }
                        , Cmd.batch [ Cmd.map ConferenceMsg conferenceCmd
                                    , Cmd.map PhoenixMsg phxCmd
                                    ]
                        )

        PhoenixMsg msg ->
            let
                ( phxSocket, phxCmd ) =
                    Phoenix.Socket.update msg model.phxSocket
            in
                ( { model | phxSocket = phxSocket }
                , Cmd.map PhoenixMsg phxCmd
                )


-- VIEW

view : Model -> Html Msg
view model =
    div [ class "jumbotron" ]
        [ h1 [ ] [ text ("Welcome, " ++ model.clientName ++ "!") ]
        , p [ ] [ text "Talkbox is a proof of concept in building browser-based telephony applications using functional programming languages." ]
        --, h4 [] [ text "Elm" ]
        --, p [] [ text model.status ]
        --, h4 [] [ text "Twilio" ]
        --, p [] [ text (toString model.twilioStatus) ]
        --, h4 [] [ text "Conference" ]
        --, p [] [ text (toString model.conferenceStatus) ]
        , case model.conference of
              Nothing ->
                  Html.map LineMsg (Line.view model.line)

              Just conference ->
                  case conference.pending_participant of
                      Nothing ->
                          p [ ]
                            [ Html.map ConferenceMsg (Conference.view conference)
                            , Html.map LineMsg (Line.view model.line)
                            ]

                      Just _ ->
                          p [ ]
                            [ Html.map ConferenceMsg (Conference.view conference) ]
        ]


-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ Twilio.statusChanged TwilioStatusChanged
    , Phoenix.Socket.listen model.phxSocket PhoenixMsg
    ]


-- JSON

encodedCall: String -> String -> JsDecode.Value
encodedCall callee user =
    JsEncode.object
      [ ( "callee", JsEncode.string callee )
      , ( "user", JsEncode.string user )
      ]


encodedPendingParticipantReference: Conference.Model -> Conference.CallLeg -> JsDecode.Value
encodedPendingParticipantReference conference callLeg =
    JsEncode.object
      [ ( "conference", JsEncode.string conference.identifier )
      , ( "chair", JsEncode.string conference.chair.identifier )
      , ( "pending_participant", JsEncode.string callLeg.identifier )
      ]


encodedParticipantReference: Conference.Model -> Conference.CallLeg -> JsDecode.Value
encodedParticipantReference conference callLeg =
    JsEncode.object
      [ ( "conference", JsEncode.string conference.identifier )
      , ( "chair", JsEncode.string conference.chair.identifier )
      , ( "call_sid", JsEncode.string (Maybe.withDefault "" callLeg.callSid) )
      ]


decodeCallRequestFailure: JsDecode.Decoder String
decodeCallRequestFailure =
  JsDecode.at ["reason"] JsDecode.string


decodeTwilioToken: JsDecode.Decoder String
decodeTwilioToken =
  JsDecode.at ["token"] JsDecode.string
