module Script exposing (..)

-- This is where the magic happens

import Json.Decode as Decode exposing (Value, Decoder, (:=), decodeValue)
import Json.Decode.Extra as Extra
import Json.Encode as Encode
import Script.Worker as Worker
import Script.Supervisor as Supervisor exposing (WorkerId, SupervisorMsg(..))
import Html.App
import Html exposing (Html)


type alias ParallelProgram workerModel workerMsg supervisorModel supervisorMsg =
    { worker :
        { update : workerMsg -> workerModel -> ( workerModel, Worker.Cmd )
        , decode : Value -> workerMsg
        , init : ( workerModel, Worker.Cmd )
        , subscriptions : workerModel -> Sub workerMsg
        }
    , supervisor :
        { update : supervisorMsg -> supervisorModel -> ( supervisorModel, Supervisor.Cmd )
        , decode : SupervisorMsg -> supervisorMsg
        , init : ( supervisorModel, Supervisor.Cmd )
        , subscriptions : supervisorModel -> Sub supervisorMsg
        , view : supervisorModel -> Html supervisorMsg
        }
    , receive : Sub Value
    , send : Value -> Cmd Value
    }


messageDecoder : Decoder ( Bool, Maybe WorkerId, Value )
messageDecoder =
    Decode.object3 (,,)
        ("forWorker" := Decode.bool)
        ("workerId" := (Extra.maybeNull Decode.string))
        ("data" := Decode.value)


type Role workerModel supervisorModel
    = Supervisor workerModel supervisorModel
    | Worker workerModel supervisorModel
    | Uninitialized


workerUpdate :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> workerModel
    -> supervisorModel
    -> workerMsg
    -> ( Role workerModel supervisorModel, Cmd (InternalMsg workerMsg supervisorMsg) )
workerUpdate config workerModel supervisorModel msg =
    let
        ( newModel, cmd ) =
            config.worker.update msg workerModel
    in
        ( Worker newModel supervisorModel, sendToSupervisor config cmd )


sendToSupervisor :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> Supervisor.Cmd
    -> InternalMsg workerMsg supervisorMsg
sendToSupervisor config cmd =
    send config (Supervisor.encodeCmd cmd)


sendToWorker :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> Worker.Cmd
    -> InternalMsg workerMsg supervisorMsg
sendToWorker config cmd =
    send config (Worker.encodeCmd cmd)


send :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> List Value
    -> InternalMsg workerMsg supervisorMsg
send config cmd =
    cmd
        |> Encode.list
        |> config.send
        |> Cmd.map InternalJsonMsg


supervisorUpdate :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> workerModel
    -> supervisorModel
    -> supervisorMsg
    -> ( Role workerModel supervisorModel, Cmd (InternalMsg workerMsg supervisorMsg) )
supervisorUpdate config workerModel supervisorModel msg =
    let
        ( newModel, cmd ) =
            config.supervisor.update msg supervisorModel
    in
        ( Supervisor workerModel newModel, send config (Supervisor.encodeCmd cmd) )


update :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> InternalMsg workerMsg supervisorMsg
    -> Role workerModel supervisorModel
    -> ( Role workerModel supervisorModel, Cmd (InternalMsg workerMsg supervisorMsg) )
update config internalMsg role =
    let
        jsonUpdate json role =
            case ( role, Decode.decodeValue messageDecoder json ) of
                ( _, Err err ) ->
                    Debug.crash ("Someone sent malformed JSON through the `receive` port: " ++ err)

                ( Uninitialized, Ok ( False, _, data ) ) ->
                    let
                        -- We've received a supervisor message; we must be a supervisor!
                        ( supervisorModel, initCmd ) =
                            config.supervisor.init

                        ( workerModel, _ ) =
                            config.worker.init

                        ( newRole, newCmd ) =
                            jsonUpdate json (Supervisor workerModel supervisorModel)
                    in
                        ( newRole, Cmd.batch [ sendToSupervisor config initCmd, newCmd ] )

                ( Uninitialized, Ok ( True, _, data ) ) ->
                    let
                        -- We've received a worker message; we must be a worker!
                        ( workerModel, initCmd ) =
                            config.worker.init

                        ( supervisorModel, _ ) =
                            config.supervisor.init

                        ( newRole, newCmd ) =
                            jsonUpdate json (Worker workerModel supervisorModel)
                    in
                        ( newRole, Cmd.batch [ sendToWorker config initCmd, newCmd ] )

                ( Supervisor workerModel supervisorModel, Ok ( False, maybeWorkerId, data ) ) ->
                    Debug.crash "TODO"

                --let
                --    -- We're a supervisor; process the message accordingly
                --    subMsg =
                --        case maybeWorkerId of
                --            Nothing ->
                --                FromOutside data
                --            Just workerId ->
                --                FromWorker workerId data
                --    ( newModel, cmd ) =
                --        supervisorUpdate config workerModel supervisorModel (config.supervisor.decode subMsg)
                --in
                --    ( Supervisor workerModel newModel, sendToSupervisor config cmd )
                ( Worker workerModel supervisorModel, Ok ( True, Nothing, data ) ) ->
                    Debug.crash "TODO"

                --let
                --    -- We're a worker; process the message accordingly
                --    ( newModel, cmd ) =
                --        workerUpdate config workerModel supervisorModel (config.worker.decode data)
                --in
                --    ( Worker newModel supervisorModel, sendToWorker config cmd )
                ( Worker _ _, Ok ( True, Just _, data ) ) ->
                    Debug.crash "Received workerId in a message intended for a worker. Worker messages should never include a workerId, as workers should never rely on knowing their own workerId values!"

                ( Worker _ _, Ok ( False, _, _ ) ) ->
                    Debug.crash "Received supervisor message while running as worker."

                ( Supervisor _ _, Ok ( True, _, _ ) ) ->
                    Debug.crash "Received worker message while running as supervisor."
    in
        case ( role, internalMsg ) of
            ( Worker workerModel supervisorModel, InternalWorkerMsg msg ) ->
                workerUpdate config workerModel supervisorModel msg

            ( Supervisor workerModel supervisorModel, InternalSupervisorMsg msg ) ->
                supervisorUpdate config workerModel supervisorModel msg

            ( Worker workerModel supervisorModel, InternalSupervisorMsg msg ) ->
                Debug.crash ("Received an internal supervisor message as a worker!" ++ toString msg)

            ( Supervisor workerModel supervisorModel, InternalWorkerMsg msg ) ->
                Debug.crash ("Received an internal worker message as a supervisor: " ++ toString msg)

            ( Uninitialized, InternalSupervisorMsg msg ) ->
                Debug.crash ("Received an internal supervisor message when uninitialized!" ++ toString msg)

            ( Uninitialized, InternalWorkerMsg msg ) ->
                Debug.crash ("Received an internal worker message when uninitialized: " ++ toString msg)

            ( _, InternalJsonMsg json ) ->
                jsonUpdate json role


program : ParallelProgram workerModel workerMsg supervisorModel supervisorMsg -> Program Never
program config =
    Html.App.program
        { init = ( Uninitialized, Cmd.none )
        , view = wrapView config.supervisor.view >> Maybe.withDefault (Html.text "")
        , update = update config
        , subscriptions =
            wrapSubscriptions config.receive
                config.worker.subscriptions
                config.supervisor.subscriptions
        }


type InternalMsg workerMsg supervisorMsg
    = InternalSupervisorMsg supervisorMsg
    | InternalWorkerMsg workerMsg
    | InternalJsonMsg Value


wrapView : (supervisorModel -> Html supervisorMsg) -> Role workerModel supervisorModel -> Maybe (Html (InternalMsg workerMsg supervisorMsg))
wrapView view role =
    case role of
        Supervisor _ supervisorModel ->
            supervisorModel
                |> view
                |> Html.App.map InternalSupervisorMsg
                |> Just

        Worker workerModel supervisorModel ->
            -- Workers can't have views
            Nothing

        Uninitialized ->
            -- We don't get a view until we initialize
            Nothing


wrapSubscriptions :
    Sub Value
    -> (workerModel -> Sub workerMsg)
    -> (supervisorModel -> Sub supervisorMsg)
    -> Role workerModel supervisorModel
    -> Sub (InternalMsg workerMsg supervisorMsg)
wrapSubscriptions receive workerSubscriptions supervisorSubscriptions role =
    let
        receiveJson =
            Sub.map InternalJsonMsg receive
    in
        case role of
            Worker workerModel _ ->
                Sub.batch
                    [ receiveJson
                    , Sub.map InternalWorkerMsg (workerSubscriptions workerModel)
                    ]

            Supervisor _ supervisorModel ->
                Sub.batch
                    [ receiveJson
                    , Sub.map InternalSupervisorMsg (supervisorSubscriptions supervisorModel)
                    ]

            Uninitialized ->
                receiveJson
