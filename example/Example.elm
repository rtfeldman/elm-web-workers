module Example (..) where

import Signal exposing (Signal)
import Json.Encode as Encode exposing (Value)
import Json.Decode as Decode exposing ((:=))
import Script
import Set exposing (Set)
import Script.Supervisor as Supervisor exposing (WorkerId, SupervisorMsg(..))
import Script.Worker as Worker
import String


type alias WorkerModel =
  { id : String }


type alias SupervisorModel =
  { messagesReceived : List String
  , workerIds : Set WorkerId
  }


updateWorker : Value -> WorkerModel -> ( WorkerModel, Worker.Cmd )
updateWorker data model =
  case Decode.decodeValue Decode.string data of
    Ok id ->
      ( { model | id = id }, Worker.send (Encode.string ("Hi, my name is Worker " ++ id ++ "!")) )

    Err err ->
      ( model, Worker.send (Encode.string ("Error on worker " ++ model.id ++ ": " ++ err)) )


updateSupervisor : SupervisorMsg -> SupervisorModel -> ( SupervisorModel, Supervisor.Cmd )
updateSupervisor supervisorMsg model =
  case supervisorMsg of
    FromWorker workerId data ->
      case Decode.decodeValue Decode.string data of
        Ok str ->
          ( model, Supervisor.emit (Encode.string ("worker[" ++ workerId ++ "] says: " ++ str)) )

        Err err ->
          ( model, Supervisor.emit (Encode.string ("worker[" ++ workerId ++ "] sent malformed example data!")) )

    FromOutside data ->
      case Decode.decodeValue (Decode.object2 (,) ("msgType" := Decode.string) ("data" := Decode.string)) data of
        Ok ( "echo", msg ) ->
          let
            newMessagesReceived =
              model.messagesReceived ++ [ msg ]

            output =
              "Here are all the messages I've received so far:\n"
                ++ (String.join "\n" newMessagesReceived)
          in
            ( { model | messagesReceived = newMessagesReceived }, Supervisor.emit (Encode.string output) )

        Ok ( "spawn", workerId ) ->
          ( { model | workerIds = Set.insert workerId model.workerIds }
          , Supervisor.send workerId (Encode.string workerId)
          )

        Ok ( msgType, msg ) ->
          Debug.crash ("Urecognized msgType: " ++ msgType ++ " with data: " ++ msg)

        Err err ->
          ( model, Supervisor.emit (Encode.string ("Error decoding message; error was: " ++ err)) )


port sendMessage : Signal Value
port sendMessage =
  Script.start
    { worker =
        { update = updateWorker
        , init = ( (WorkerModel "0"), Worker.none )
        }
    , supervisor =
        { update = updateSupervisor
        , init = ( (SupervisorModel [] Set.empty), Supervisor.none )
        }
    , receiveMessage = receiveMessage
    }


port receiveMessage : Signal Value
