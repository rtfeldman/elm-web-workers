module Script exposing (..)

-- This is where the magic happens

import Json.Decode as Decode exposing (Value, Decoder, (:=), decodeValue)
import Json.Decode.Extra as Extra
import Json.Encode as Encode
import Script.Worker as Worker
import Script.Supervisor as Supervisor exposing (WorkerId, SupervisorMsg(..))
import Html.App
import Html exposing (Html)


type alias ParallelProgram workerModel supervisorModel =
    { worker :
        { update : Value -> workerModel -> ( workerModel, Worker.Cmd )
        , init : ( workerModel, Worker.Cmd )
        , subscriptions : workerModel -> Sub Value
        }
    , supervisor :
        { update : SupervisorMsg -> supervisorModel -> ( supervisorModel, Supervisor.Cmd )
        , init : ( supervisorModel, Supervisor.Cmd )
        , subscriptions : supervisorModel -> Sub Value
        , view : supervisorModel -> Html Value
        }
    , receive : Sub Value
    , send : Value -> Cmd Value
    }


messageDecoder : Decoder ( Bool, Maybe WorkerId, Value )
messageDecoder =
    Decode.object3 (,,) ("forWorker" := Decode.bool) ("workerId" := (Extra.maybeNull Decode.string)) ("data" := Decode.value)


type Role workerModel supervisorModel
    = Supervisor workerModel supervisorModel
    | Worker workerModel supervisorModel
    | Uninitialized


program : ParallelProgram workerModel supervisorModel -> Program Never
program config =
    let
        supervisorCmd : Supervisor.Cmd -> Cmd Value
        supervisorCmd cmd =
            cmd
                |> Supervisor.encodeCmd
                |> Encode.list
                |> config.send

        workerCmd : Worker.Cmd -> Cmd Value
        workerCmd cmd =
            cmd
                |> Worker.encodeCmd
                |> Encode.list
                |> config.send

        --update : Value -> Role workerModel -> ( Role workerModel supervisorModel, Cmd Value )
        update msg role =
            case ( role, Decode.decodeValue messageDecoder msg ) of
                ( _, Err err ) ->
                    Debug.crash ("Malformed JSON received: " ++ err)

                ( Uninitialized, Ok ( False, _, data ) ) ->
                    let
                        -- We've received a supervisor message; we must be a supervisor!
                        ( supervisorModel, initCmd ) =
                            config.supervisor.init

                        ( workerModel, _ ) =
                            config.worker.init

                        ( newRole, newCmd ) =
                            update msg (Supervisor workerModel supervisorModel)
                    in
                        ( newRole, Cmd.batch [ supervisorCmd initCmd, newCmd ] )

                ( Uninitialized, Ok ( True, _, data ) ) ->
                    let
                        -- We've received a worker message; we must be a worker!
                        ( workerModel, initCmd ) =
                            config.worker.init

                        ( supervisorModel, _ ) =
                            config.supervisor.init

                        ( newRole, newCmd ) =
                            update msg (Worker workerModel supervisorModel)
                    in
                        ( newRole, Cmd.batch [ workerCmd initCmd, newCmd ] )

                ( Supervisor workerModel supervisorModel, Ok ( False, maybeWorkerId, data ) ) ->
                    let
                        -- We're a supervisor; process the message accordingly
                        subMsg =
                            case maybeWorkerId of
                                Nothing ->
                                    FromOutside data

                                Just workerId ->
                                    FromWorker workerId data

                        ( newModel, cmd ) =
                            config.supervisor.update subMsg supervisorModel
                    in
                        ( Supervisor workerModel newModel, supervisorCmd cmd )

                ( Worker model supervisorModel, Ok ( True, Nothing, data ) ) ->
                    let
                        -- We're a worker; process the message accordingly
                        ( newModel, cmd ) =
                            config.worker.update data model
                    in
                        ( Worker newModel supervisorModel, workerCmd cmd )

                ( Worker _ _, Ok ( True, Just _, data ) ) ->
                    Debug.crash "Received workerId message intended for a worker."

                ( Worker _ _, Ok ( False, _, _ ) ) ->
                    Debug.crash "Received supervisor message while running as worker."

                ( Supervisor _ _, Ok ( True, _, _ ) ) ->
                    Debug.crash "Received worker message while running as supervisor."
    in
        Html.App.program
            { init = ( Uninitialized, Cmd.none )
            , view = wrapView config.supervisor.view >> Maybe.withDefault (Html.text "")
            , update = update
            , subscriptions =
                wrapSubscriptions config.receive
                    config.worker.subscriptions
                    config.supervisor.subscriptions
            }


wrapView : (supervisorModel -> Html Value) -> Role workerModel supervisorModel -> Maybe (Html Value)
wrapView view role =
    case role of
        Supervisor _ supervisorModel ->
            Just (view supervisorModel)

        Worker workerModel supervisorModel ->
            -- Workers can't have views
            Nothing

        Uninitialized ->
            -- We don't get a view until we initialize
            Nothing


wrapSubscriptions : Sub Value -> (workerModel -> Sub Value) -> (supervisorModel -> Sub Value) -> Role workerModel supervisorModel -> Sub Value
wrapSubscriptions receive workerSubscriptions supervisorSubscriptions role =
    case role of
        Supervisor _ supervisorModel ->
            Sub.batch [ receive, supervisorSubscriptions supervisorModel ]

        Worker workerModel _ ->
            Sub.batch [ receive, workerSubscriptions workerModel ]

        Uninitialized ->
            receive
