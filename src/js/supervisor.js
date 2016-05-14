var Worker = typeof Worker === "undefined" ? require("webworker-threads").Worker : Worker;

function Supervisor(elmPath, elmModuleName, args, sendMessagePortName, receiveMessagePortName, workerPath) {
  if (typeof workerPath === "undefined") {
    workerPath = (typeof require !== "undefined" && require.resolve) ? require.resolve("./worker.js") : "worker.js";
  }

  Elm = typeof Elm === "undefined" ? require(elmPath) : Elm;

  var elmApp = Elm[elmModuleName].worker(args);

  if (typeof sendMessagePortName === "undefined") {
    sendMessagePortName = "send";
  } else if (typeof sendMessagePortName !== "string") {
    throw new Error("Invalid sendMessagePortName: " + sendMessagePortName);
  }

  if (typeof receiveMessagePortName === "undefined") {
    receiveMessagePortName = "receive";
  } else if (typeof receiveMessagePortName !== "string") {
    throw new Error("Invalid receiveMessagePortName: " + receiveMessagePortName);
  }

  // Validate that elmApp looks right.
  if (typeof elmApp !== "object") {
    throw new Error("Invalid elmApp: " + elmApp);
  } else if (typeof elmApp.ports !== "object") {
    throw new Error("The provided elmApp is missing a `ports` field.");
  }

  [sendMessagePortName, receiveMessagePortName].forEach(function(portName) {
    if (typeof elmApp.ports[portName] !== "object") {
      throw new Error("The provided elmApp does not have a valid a port called `" + portName + "`.");
    }
  });

  // Set up methods

  var ports = elmApp.ports;
  var subscribe = ports[sendMessagePortName].subscribe;
  var send = ports[receiveMessagePortName].send
  var listeners = {};

  function emit(msgType, data) {
    if (typeof listeners[msgType] === "object") {
      listeners[msgType].forEach(function(callback) {
        callback(data);
      });
    }
  }

  this.on = function on(msgType, callback) {
    if (typeof listeners[msgType] === "undefined") {
      listeners[msgType] = [callback];
    } else {
      listeners[msgType].push(callback);
    }
  }

  this.off = function off(msgType) {
    delete listeners[msgType];
  }

  var started = false; // CAUTION: this gets mutated!
  var sendQueue = []; // CAUTION: this gets mutated!

  this.start = function() {
    if (started) {
      throw new Error("Attempted to start a supervisor that was already started!");
    } else {
      var workerConfig = JSON.stringify({
        elmPath: elmPath,
        elmModuleName: elmModuleName,
        receiveMessagePortName: receiveMessagePortName,
        sendMessagePortName: sendMessagePortName,
        args: args
      });

      supervise(subscribe, send, emit, workerPath, workerConfig);
    }

    // Clear out the send queue.
    // NOTE: we must wrap this in a setTimeout, as sending immediately after
    // calling start() drops the messages on Node.js for some as-yet unknown reason.
    setTimeout(function() {
      sendQueue.forEach(function(thunk) { thunk() });

      sendQueue = undefined;
    }, 0);
  }

  this.send = function(data) {
    if (typeof sendQueue === "undefined") {
      return send({forWorker: false, workerId: null, data: data});
    } else {
      // If we haven't started yet, enqueue the messages for sending later.
      sendQueue.push(function() { send({forWorker: false, workerId: null, data: data}); });
    }
  }

  this.Elm = Elm;

  return this;
}

function supervise(subscribe, send, emit, workerPath, workerConfig) {
  var workers = {};

  function emitClose(msg) {
    emit("close", msg);
  }

  function emitMessage(msg) {
    emit("emit", msg);
  }

  function terminateWorkers() {
    Object.keys(workers).forEach(function(id) {
      workers[id].terminate();
    });
  }

  function handleMessage(msg) {
    switch (msg.cmd) {
      case "TERMINATE":
        terminateWorkers();

        // We're done!
        return emitClose(null);

      case "EMIT":
        return emitMessage(msg.data);

      case "SEND_TO_WORKER":
        var workerId = msg.workerId;

        if (typeof workerId !== "string") {
          terminateWorkers();

          return emitClose("Error: Cannot send message " + msg + " to workerId `" + workerId + "`!");
        } else {
          var message = {cmd: "SEND_TO_WORKER", data: msg.data};

          if (workers.hasOwnProperty(workerId)) {
            return workers[workerId].postMessage(message);
          } else {
            // This workerId is unknown to us; init a new worker before sending.
            var worker = new Worker(workerPath);

            worker.onerror = function(err) {
              console.error("Exception in worker[" + workerId + "]: " + JSON.stringify(err));
            }

            worker.onmessage = function(event) {
              var data = event.data || {};
              var contents = data.contents;

              switch (data.cmd) {
                case "WORKER_ERROR":
                  return console.error("Error in worker[" + workerId + "]: " + contents);

                case "MESSAGE_FROM_WORKER":
                  if (typeof contents === "undefined") {
                    return console.error("Received `undefined` as a message from worker[" + workerId + "]");
                  } else {
                    contents.forEach(function(content) {
                      // When the worker sends a message, tag it with this workerId
                      // and then send it along for the supervisor to handle.
                      return send({forWorker: false, workerId: workerId, data: content});
                    });
                  }

                default:
                  throw new Error("Received unrecognized msgType from worker[" + workerId + "]: " + contents);
              }
            };

            // Record this new worker in the lookup table.
            workers[workerId] = worker;

            // Give the worker a tick to initialize before posting the message.
            return setTimeout(function() {
              worker.postMessage({cmd: "INIT_WORKER", data: workerConfig});

              return setTimeout(function() {
                worker.postMessage(message);
              });
            }, 0);
          }
        }

      default:
        throw new Error("Supervisor attempted to handle unrecognized command: " + msg.cmd);
    }
  }

  subscribe(function(messages) {
    try {
      messages.forEach(handleMessage);
    } catch (err) {
      terminateWorkers();
      emitClose(err);
    }
  });
}

if (typeof module === "object") {
  module.exports = Supervisor;
}
