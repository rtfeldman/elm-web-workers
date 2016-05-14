console.log("I AM A WORKER");

var receiveMessagePortName;

module = typeof module === "undefined" ? {} : module;
setTimeout = typeof setTimeout === "undefined" ? function(callback) { return callback() } : setTimeout;

function sendMessage(message) {
  console.log("POSTM")
  self.postMessage(message);
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

          elmApp = Elm[config.elmModuleName].worker(config.args);

          elmApp.ports[config.sendMessagePortName].subscribe(sendMessage);
        } catch(err) {
          throw new Error("Error initializing Elm in worker: " + err);
        }
      } else {
        throw new Error("Worker attempted to initialize twice!");
      }

      break;

    case "SEND_TO_WORKER":
      if (typeof elmApp === "undefined") {
        throw new Error("Canot send() to a worker that has not yet been initialized!");
      }

      try {
        elmApp.ports[receiveMessagePortName].send({forWorker: true, workerId: null, data: msg.data});
      } catch (err) {
        throw new Error("Error attempting to send message to Elm Worker: " + err);
      }

      break;

    default:
      throw new Error("Unrecognized worker command: " + msg.cmd);
  }
};
