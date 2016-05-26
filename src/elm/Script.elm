module Script exposing (..)

-- This is where the magic happens

import Json.Decode as Decode exposing (Value, Decoder, (:=), decodeValue)
import Json.Decode.Extra as Extra
import Json.Encode as Encode
import Script.Worker as Worker
import Script.Supervisor as Supervisor exposing (WorkerId)
import Html.App
import Html exposing (Html)


type alias ParallelProgram workerModel workerMsg supervisorModel supervisorMsg =
    { worker :
        { update : workerMsg -> workerModel -> ( workerModel, Cmd workerMsg )
        , decode : Value -> workerMsg
        , init : ( workerModel, Cmd workerMsg )
        , subscriptions : workerModel -> Sub workerMsg
        }
    , supervisor :
        { update : supervisorMsg -> supervisorModel -> ( supervisorModel, Cmd supervisorMsg )
        , decode : WorkerId -> Value -> supervisorMsg
        , init : ( supervisorModel, Cmd supervisorMsg )
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
    -> ( Role workerModel supervisorModel, Cmd workerMsg )
workerUpdate config workerModel supervisorModel msg =
    let
        ( newModel, cmd ) =
            config.worker.update msg workerModel
    in
        ( Worker newModel supervisorModel, cmd )


supervisorUpdate :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> workerModel
    -> supervisorModel
    -> supervisorMsg
    -> ( Role workerModel supervisorModel, Cmd supervisorMsg )
supervisorUpdate config workerModel supervisorModel msg =
    let
        ( newModel, cmd ) =
            config.supervisor.update msg supervisorModel
    in
        ( Supervisor workerModel newModel, cmd )


jsonUpdate :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> Value
    -> Role workerModel supervisorModel
    -> ( Role workerModel supervisorModel, Cmd (InternalMsg workerMsg supervisorMsg) )
jsonUpdate config json role =
    case ( role, Decode.decodeValue messageDecoder json ) of
        ( _, Err err ) ->
            Debug.crash ("Someone sent malformed JSON through the `receive` port: " ++ err)

        ( Uninitialized, Ok ( False, _, data ) ) ->
            let
                -- We've received a supervisor message; we must be a supervisor!
                ( supervisorModel, supervisorInitCmd ) =
                    config.supervisor.init

                workerModel =
                    fst config.worker.init

                ( newRole, newCmd ) =
                    jsonUpdate config json (Supervisor workerModel supervisorModel)
            in
                ( newRole, Cmd.batch [ initCmd, newCmd ] )

        _ ->
            Debug.crash "TODO"



--( Uninitialized, Ok ( True, _, data ) ) ->
--    let
--        -- We've received a worker message; we must be a worker!
--        ( workerModel, initCmd ) =
--            config.worker.init
--        supervisorModel =
--            fst config.supervisor.init
--        ( newRole, newCmd ) =
--            jsonUpdate config json (Worker workerModel supervisorModel)
--    in
--        ( newRole, Cmd.batch [ initCmd, newCmd ] )
--( Supervisor workerModel supervisorModel, Ok ( False, Just workerId, data ) ) ->
--    let
--        -- We're a supervisor; process the message accordingly
--        ( newModel, cmd ) =
--            supervisorUpdate config workerModel supervisorModel (config.supervisor.decode workerId data)
--    in
--        ( Supervisor workerModel newModel, cmd )
--( Worker workerModel supervisorModel, Ok ( True, Nothing, data ) ) ->
--    Debug.crash "TODO"
----let
----    -- We're a worker; process the message accordingly
----    ( newModel, cmd ) =
----        workerUpdate config workerModel supervisorModel (config.worker.decode data)
----in
----    ( Worker newModel supervisorModel, sendToWorker config cmd )
--( Worker _ _, Ok ( True, Just _, data ) ) ->
--    Debug.crash "Received workerId in a message intended for a worker. Worker messages should never include a workerId, as workers should never rely on knowing their own workerId values!"
--( Worker _ _, Ok ( False, _, _ ) ) ->
--    Debug.crash "Received supervisor message while running as worker."
--( Supervisor _ _, Ok ( False, Nothing, _ ) ) ->
--    Debug.crash "Received supervisor message without a workerId."
--( Supervisor _ _, Ok ( True, _, _ ) ) ->
--    Debug.crash "Received worker message while running as supervisor."


update :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> InternalMsg workerMsg supervisorMsg
    -> Role workerModel supervisorModel
    -> ( Role workerModel supervisorModel, Cmd (InternalMsg workerMsg supervisorMsg) )
update config internalMsg role =
    case ( role, internalMsg ) of
        ( Worker workerModel supervisorModel, InternalWorkerMsg msg ) ->
            Debug.crash "TODO"

        --let
        --    ( newModel, workerMsg ) =
        --        workerUpdate config workerModel supervisorModel msg
        --in
        --    ( newModel, sendToWorker config workerMsg )
        ( Supervisor workerModel supervisorModel, InternalSupervisorMsg msg ) ->
            Debug.crash "TODO"

        --let
        --    ( newModel, supervisorMsg ) =
        --        supervisorUpdate config workerModel supervisorModel msg
        --in
        --    ( newModel, sendToSupervisor config supervisorMsg )
        ( Worker workerModel supervisorModel, InternalSupervisorMsg msg ) ->
            Debug.crash ("Received an internal supervisor message as a worker!" ++ toString msg)

        ( Supervisor workerModel supervisorModel, InternalWorkerMsg msg ) ->
            Debug.crash ("Received an internal worker message as a supervisor: " ++ toString msg)

        ( Uninitialized, InternalSupervisorMsg msg ) ->
            Debug.crash ("Received an internal supervisor message when uninitialized!" ++ toString msg)

        ( Uninitialized, InternalWorkerMsg msg ) ->
            Debug.crash ("Received an internal worker message when uninitialized: " ++ toString msg)

        ( _, InternalJsonMsg json ) ->
            jsonUpdate config json role


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
