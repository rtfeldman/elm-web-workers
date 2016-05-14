var module = typeof module === "undefined" ? {} : module;
var setTimeout = typeof setTimeout === "undefined" ? function(callback) { return callback() } : setTimeout;
var Elm;
var elmApp;
var sendMessagePortName;
var receiveMessagePortName;

function sendError(err) {
  self.postMessage({cmd: "WORKER_ERROR", contents: err});
}

function sendMessage(message) {
  self.postMessage({cmd: "MESSAGE_FROM_WORKER", contents: message});
}

self.onmessage = function(event) {
  var msg = event.data;

  switch (msg.cmd) {
    case "INIT_WORKER":
      if (typeof elmApp === "undefined") {
        var config = JSON.parse(msg.data);

        try {
          importScripts(config.elmPath);

          receiveMessagePortName = config.receiveMessagePortName;

          Elm = typeof Elm === "undefined" ? module.exports : Elm;

          elmApp =
              Elm[config.elmModuleName].worker()

          // elmApp =
          //   typeof config.args === "undefined"
          //     ? Elm[config.elmModuleName].worker()
          //     : Elm[config.elmModuleName].worker(config.args);

          elmApp.ports[config.sendMessagePortName].subscribe(sendMessage);
        } catch(err) {
          sendError("Error initializing Elm in worker: " + err);
        }
      } else {
        sendError("Worker attempted to initialize twice!");
      }

      break;

    case "SEND_TO_WORKER":
      if (typeof elmApp === "undefined") {
        sendError("Canot send() to a worker that has not yet been initialized!");
      }

      try {
        elmApp.ports[receiveMessagePortName].send({forWorker: true, workerId: null, data: msg.data});
      } catch (err) {
        sendError("Error attempting to send message to Elm Worker: " + err);
      }

      break;

    default:
      sendError("Unrecognized worker command: " + msg.cmd);
  }
};
