module Script.Supervisor exposing (Cmd, terminate, send, emit, batch, none, WorkerId, SupervisorMsg(..), encodeCmd)

{-| Helpers for running supervisors.

@docs Cmd, terminate, send, emit, batch, none, WorkerId, SupervisorMsg, encodeCmd
-}

-- This is where the magic happens

import Json.Encode as Encode exposing (Value)


{-| -}
type alias WorkerId =
    String


{-| -}
type SupervisorMsg
    = FromWorker WorkerId Value
    | FromOutside Value


{-| A command the supervisor can run.
-}
type Cmd
    = Terminate
    | Send WorkerId Value
    | Emit Value
    | Batch (List Cmd)


{-| Serialize a `Cmd` into a list of `Json.Value` instances.
-}
encodeCmd : Cmd -> List Value
encodeCmd cmd =
    case cmd of
        Terminate ->
            -- Sending a null workerId and null data terminates the supervisor.
            [ Encode.object
                [ ( "cmd", Encode.string "TERMINATE" )
                , ( "workerId", Encode.null )
                , ( "data", Encode.null )
                ]
            ]

        Emit data ->
            -- Sending a null workerId with String data emits it.
            [ Encode.object
                [ ( "cmd", Encode.string "EMIT" )
                , ( "workerId", Encode.null )
                , ( "data", data )
                ]
            ]

        Send workerId data ->
            [ Encode.object
                [ ( "cmd", Encode.string "SEND_TO_WORKER" )
                , ( "workerId", Encode.string workerId )
                , ( "data", data )
                ]
            ]

        Batch cmds ->
            List.concatMap encodeCmd cmds


{-| Terminate the supervisor and all workers.
-}
terminate : Cmd
terminate =
    Terminate


{-| Send a `Json.Value` to a particular worker.
-}
send : WorkerId -> Value -> Cmd
send =
    Send


{-| Combine several supervisor commands.
-}
batch : List Cmd -> Cmd
batch =
    Batch


{-| -}
emit : Value -> Cmd
emit =
    Emit


{-| Do nothing.
-}
none : Cmd
none =
    batch []
