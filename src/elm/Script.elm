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


type ScriptCmd
    = SupervisorCmd Supervisor.Cmd
    | WorkerCmd Worker.Cmd
    | None



--program : ParallelProgram workerModel supervisorModel -> Program Never


program config =
    let
        --handleMessage : Value -> ( Role workerModel supervisorModel, ScriptCmd ) -> ( Role workerModel supervisorModel, ScriptCmd )
        handleMessage msg ( role, _ ) =
            case ( role, Decode.decodeValue messageDecoder msg ) of
                ( _, Err err ) ->
                    Debug.crash ("Malformed JSON received: " ++ err)

                ( Uninitialized, Ok ( False, _, data ) ) ->
                    let
                        -- We've received a supervisor message; we must be a supervisor!
                        ( model, cmd ) =
                            config.supervisor.init

                        ( workerModel, _ ) =
                            config.worker.init
                    in
                        case handleMessage msg ( (Supervisor workerModel model), None ) of
                            ( newRole, SupervisorCmd newCmd ) ->
                                ( newRole, SupervisorCmd (Supervisor.batch [ cmd, newCmd ]) )

                            ( _, WorkerCmd _ ) ->
                                Debug.crash "On init, received a worker command instead of the expected supervisor command"

                            ( _, None ) ->
                                Debug.crash "On init, received a None command instead of the expected supervisor command"

                ( Uninitialized, Ok ( True, _, data ) ) ->
                    let
                        -- We've received a worker message; we must be a worker!
                        ( model, cmd ) =
                            config.worker.init

                        ( supervisorModel, _ ) =
                            config.supervisor.init
                    in
                        case handleMessage msg ( (Worker model supervisorModel), None ) of
                            ( newRole, WorkerCmd newCmd ) ->
                                ( newRole, WorkerCmd (Worker.batch [ cmd, newCmd ]) )

                            ( _, SupervisorCmd _ ) ->
                                Debug.crash "On init, received a supervisor command instead of the expected worker command"

                            ( _, None ) ->
                                Debug.crash "On init, received a None command instead of the expected worker command"

                ( Supervisor workerModel model, Ok ( False, maybeWorkerId, data ) ) ->
                    let
                        -- We're a supervisor; process the message accordingly
                        subMsg =
                            case maybeWorkerId of
                                Nothing ->
                                    FromOutside data

                                Just workerId ->
                                    FromWorker workerId data

                        ( newModel, cmd ) =
                            config.supervisor.update subMsg model
                    in
                        ( Supervisor workerModel newModel, SupervisorCmd cmd )

                ( Worker model supervisorModel, Ok ( True, Nothing, data ) ) ->
                    let
                        -- We're a worker; process the message accordingly
                        ( newModel, cmd ) =
                            config.worker.update data model
                    in
                        ( Worker newModel supervisorModel, WorkerCmd cmd )

                ( Worker _ _, Ok ( True, Just _, data ) ) ->
                    Debug.crash ("Received workerId message intended for a worker.")

                ( Worker _ _, Ok ( False, _, _ ) ) ->
                    Debug.crash ("Received supervisor message while running as worker.")

                ( Supervisor _ _, Ok ( True, _, _ ) ) ->
                    Debug.crash ("Received worker message while running as supervisor.")
    in
        --Signal.foldp handleMessage ( Uninitialized, None ) config.receiveMessage
        --    |> Signal.filterMap (snd >> cmdToMsg)
        --        Encode.null
        Html.App.program
            { init = ( ( Uninitialized, None ), Cmd.none )
            , view = wrapView config.supervisor.view >> Maybe.withDefault (Html.text "")
            , update = handleMessage
            , subscriptions =
                wrapSubscriptions config.message
                    config.worker.subscriptions
                    config.supervisor.subscriptions
            }


wrapView : (supervisorModel -> Html Value) -> ( Role workerModel supervisorModel, ScriptCmd ) -> Maybe (Html Value)
wrapView view ( role, _ ) =
    case role of
        Supervisor workerModel supervisorModel ->
            Just (view supervisorModel)

        Worker workerModel supervisorModel ->
            -- Workers can't have views
            Nothing

        Uninitialized ->
            -- We don't get a view until we initialize
            Nothing



--wrapSubscriptions : Sub Value -> (workerModel -> Sub Value) -> (supervisorModel -> Sub Value) -> ( Role workerModel supervisorModel, ScriptCmd ) -> Sub Value


wrapSubscriptions receiveMessage workerSubscriptions supervisorSubscriptions ( role, _ ) =
    case role of
        Supervisor _ supervisorModel ->
            Sub.batch [ receiveMessage, supervisorSubscriptions supervisorModel ]

        Worker workerModel _ ->
            Sub.batch [ receiveMessage, workerSubscriptions workerModel ]

        Uninitialized ->
            receiveMessage


cmdToMsg : ScriptCmd -> Maybe Value
cmdToMsg rawCmd =
    case rawCmd of
        SupervisorCmd cmd ->
            cmd
                |> Supervisor.encodeCmd
                |> Encode.list
                |> Just

        WorkerCmd cmd ->
            cmd
                |> Worker.encodeCmd
                |> Encode.list
                |> Just

        None ->
            Nothing
