port module Example exposing (..)

-- This is where the magic happens

import Json.Encode as Encode exposing (Value)
import Script exposing (WorkerId, WorkerCommands, SupervisorCommands)
import Set exposing (Set)
import Example.Worker as Worker
import Example.Supervisor as Supervisor
import Html


main : Program Never
main =
    Script.program
        { worker =
            { update = Worker.update
            , receive = Worker.receive
            , init = ( (Worker.Model "0"), Cmd.none )
            , subscriptions = \_ -> Sub.none
            }
        , supervisor =
            { update = Supervisor.update
            , init = ( (Supervisor.Model [] Set.empty), Cmd.none )
            , receive = Supervisor.receive
            , subscriptions = \_ -> Sub.none
            , view = \_ -> Html.text "Running..."
            }
        , ports = ( send, receive identity )
        }


port send : Value -> Cmd msg


port receive : (Value -> msg) -> Sub msg
