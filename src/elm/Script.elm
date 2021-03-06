module Script exposing (ParallelProgram, program, WorkerCommands, SupervisorCommands, WorkerId)

{-|

@docs ParallelProgram, program, WorkerCommands, SupervisorCommands, WorkerId
-}

-- This is where the magic happens

import Json.Decode as Decode exposing (Value, Decoder, (:=), decodeValue)
import Json.Encode as Encode
import Html.App
import Html exposing (Html)


{-| -}
type alias WorkerId =
    String


{-| -}
type alias WorkerCommands workerMsg =
    { send : Value -> Cmd workerMsg
    , close : Cmd workerMsg
    }


{-| -}
type alias SupervisorCommands supervisorMsg =
    { send : WorkerId -> Value -> Cmd supervisorMsg
    , terminate : WorkerId -> Cmd supervisorMsg
    , close : Cmd supervisorMsg
    }


{-| -}
type alias ParallelProgram workerModel workerMsg supervisorModel supervisorMsg =
    { worker :
        { update :
            WorkerCommands workerMsg
            -> workerMsg
            -> workerModel
            -> ( workerModel, Cmd workerMsg )
        , receive : Value -> workerMsg
        , init : ( workerModel, Cmd workerMsg )
        , subscriptions : workerModel -> Sub workerMsg
        }
    , supervisor :
        { update :
            SupervisorCommands supervisorMsg
            -> supervisorMsg
            -> supervisorModel
            -> ( supervisorModel, Cmd supervisorMsg )
        , receive : WorkerId -> Value -> supervisorMsg
        , init : ( supervisorModel, Cmd supervisorMsg )
        , subscriptions : supervisorModel -> Sub supervisorMsg
        , view : supervisorModel -> Html supervisorMsg
        }
    , ports : ( Value -> Cmd Never, Sub Value )
    }


fromNever : Never -> a
fromNever a =
    fromNever a


getWorkerCommands : (Value -> Cmd Never) -> WorkerCommands msg
getWorkerCommands send =
    { send =
        \value ->
            [ ( "cmd", Encode.string "SEND_TO_SUPERVISOR" )
            , ( "data", value )
            ]
                |> Encode.object
                |> send
                |> Cmd.map fromNever
    , close =
        [ ( "cmd", Encode.string "CLOSE" )
        , ( "data", Encode.null )
        ]
            |> Encode.object
            |> send
            |> Cmd.map fromNever
    }


getSupervisorCommands : (Value -> Cmd Never) -> SupervisorCommands msg
getSupervisorCommands send =
    { send =
        \workerId value ->
            [ ( "cmd", Encode.string "SEND_TO_WORKER" )
            , ( "workerId", Encode.string workerId )
            , ( "data", value )
            ]
                |> Encode.object
                |> send
                |> Cmd.map fromNever
    , terminate =
        \workerId ->
            [ ( "cmd", Encode.string "TERMINATE" )
            , ( "workerId", Encode.string workerId )
            , ( "data", Encode.null )
            ]
                |> Encode.object
                |> send
                |> Cmd.map fromNever
    , close =
        [ ( "cmd", Encode.string "CLOSE" )
        , ( "workerId", Encode.null )
        , ( "data", Encode.null )
        ]
            |> Encode.object
            |> send
            |> Cmd.map fromNever
    }


messageDecoder : Decoder ( Bool, Maybe WorkerId, Value )
messageDecoder =
    Decode.object3 (,,)
        ("forWorker" := Decode.bool)
        ("workerId" := nullable Decode.string)
        ("data" := Decode.value)


type Role workerModel supervisorModel
    = Supervisor workerModel supervisorModel
    | Worker workerModel supervisorModel
    | Uninitialized


getUpdate :
    ParallelProgram workerModel workerMsg supervisorModel supervisorMsg
    -> InternalMsg workerMsg supervisorMsg
    -> Role workerModel supervisorModel
    -> ( Role workerModel supervisorModel, Cmd (InternalMsg workerMsg supervisorMsg) )
getUpdate config =
    let
        send =
            fst config.ports

        workerCommands =
            getWorkerCommands send

        supervisorCommands =
            getSupervisorCommands send

        workerUpdate workerModel supervisorModel msg =
            let
                ( newModel, cmd ) =
                    config.worker.update workerCommands msg workerModel
            in
                ( Worker newModel supervisorModel, Cmd.map InternalWorkerMsg cmd )

        supervisorUpdate workerModel supervisorModel msg =
            let
                ( newModel, cmd ) =
                    config.supervisor.update supervisorCommands msg supervisorModel
            in
                ( Supervisor workerModel newModel, Cmd.map InternalSupervisorMsg cmd )

        jsonUpdate config json role =
            case ( role, Decode.decodeValue messageDecoder json ) of
                ( _, Err err ) ->
                    Debug.crash ("Someone sent malformed JSON through the `receive` port: " ++ err)

                ( Uninitialized, Ok ( False, _, data ) ) ->
                    let
                        -- We've received a supervisor message; we must be a supervisor!
                        ( supervisorModel, supervisorInitCmd ) =
                            config.supervisor.init

                        initCmd =
                            Cmd.map InternalSupervisorMsg supervisorInitCmd

                        workerModel =
                            fst config.worker.init

                        ( newRole, newCmd ) =
                            jsonUpdate config json (Supervisor workerModel supervisorModel)
                    in
                        ( newRole, Cmd.batch [ initCmd, newCmd ] )

                ( Uninitialized, Ok ( True, _, data ) ) ->
                    let
                        -- We've received a worker message; we must be a worker!
                        ( workerModel, workerInitCmd ) =
                            config.worker.init

                        initCmd =
                            Cmd.map InternalWorkerMsg workerInitCmd

                        supervisorModel =
                            fst config.supervisor.init

                        ( newRole, newCmd ) =
                            jsonUpdate config json (Worker workerModel supervisorModel)
                    in
                        ( newRole, Cmd.batch [ initCmd, newCmd ] )

                ( Supervisor workerModel supervisorModel, Ok ( False, Just workerId, data ) ) ->
                    -- We're a supervisor; process the message accordingly
                    supervisorUpdate workerModel
                        supervisorModel
                        (config.supervisor.receive workerId data)

                ( Worker workerModel supervisorModel, Ok ( True, Nothing, data ) ) ->
                    -- We're a worker; process the message accordingly
                    workerUpdate workerModel
                        supervisorModel
                        (config.worker.receive data)

                ( Worker _ _, Ok ( True, Just _, data ) ) ->
                    Debug.crash "Received workerId in a message intended for a worker. Worker messages should never include a workerId, as workers should never rely on knowing their own workerId values!"

                ( Worker _ _, Ok ( False, _, _ ) ) ->
                    Debug.crash "Received supervisor message while running as worker."

                ( Supervisor _ _, Ok ( False, Nothing, _ ) ) ->
                    Debug.crash "Received supervisor message without a workerId."

                ( Supervisor _ _, Ok ( True, _, _ ) ) ->
                    Debug.crash "Received worker message while running as supervisor."
    in
        -- This is the actual update function. Everything up to this point has
        -- been prep work that only needs to be done once, not every time
        -- udpate gets called.
        \internalMsg role ->
            case ( role, internalMsg ) of
                ( Worker workerModel supervisorModel, InternalWorkerMsg msg ) ->
                    workerUpdate workerModel supervisorModel msg

                ( Supervisor workerModel supervisorModel, InternalSupervisorMsg msg ) ->
                    supervisorUpdate workerModel supervisorModel msg

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


{-| -}
program : ParallelProgram workerModel workerMsg supervisorModel supervisorMsg -> Program Never
program config =
    Html.App.program
        { init = ( Uninitialized, Cmd.none )
        , view = wrapView config.supervisor.view >> Maybe.withDefault (Html.text "")
        , update = getUpdate config
        , subscriptions =
            wrapSubscriptions (snd config.ports)
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


{-| Works just like http://package.elm-lang.org/packages/elm-community/json-extra/1.0.0/Json-Decode-Extra#maybeNull
-}
nullable : Decoder a -> Decoder (Maybe a)
nullable decoder =
    Decode.oneOf
        [ Decode.null Nothing
        , Decode.map Just decoder
        ]
