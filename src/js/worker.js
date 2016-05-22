// TODO: this still doesn't quite work right. Messages are getting dropped.
// In a browser, things work great.
// In here, not so much. Not all the threads report that they initialized
// successfully, and then even fewer greet successfully.
// onerror doesn't work, so we need to wrap everything in a try/catch
// and send a {type: error} message to the parent if something blows up.
// At least that will get us some visibility.

var receiveMessagePortName;

self.onmessage = function(event) {
  var msg = event.data;

  switch (msg.cmd) {
    case "RUN_SET_TIMEOUT_CALLBACK":
      var id = msg.data;
      var callback = setTimeouts[id];

      setTimeouts[id] = undefined;

      callback();

      break;

    case "INIT_WORKER":
      if (typeof elmApp === "undefined") {
        var config = JSON.parse(msg.data);

        try {
          module = {};

          importScripts(config.elmPath);
          var Elm = module.exports;

          receiveMessagePortName = config.receiveMessagePortName;

          elmApp = Elm[config.elmModuleName].worker(config.args);

          elmApp.ports[config.sendMessagePortName].subscribe(sendMessages);

          // Tell the supervisor we're initialized, so it can run the
          // pending message that was waiting for init to complete.
          self.postMessage({type: "initialized"});
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

  // This is mandatory somehow. #WTF
  // self.close();
};

// This is a hack to implement setTimeout on a worker by telling the supervisor
// we want a setTimeout to happen, then having the supervisor report back when
// we should run the callback. This is necessary because the generated Elm code
// relies on setTimeout functioning properly in order to yield in between work
// queue operations. If you instead polyfill setTimeout using something like
// function(callback) { return callback(); }, the behavior you get is that
// spawnLoop never yields, and thus never terminates, and the worker gets stuck.
var setTimeouts = {};
var setTimeoutId = 0;

if (typeof setTimeout === "undefined") {
  setTimeout = function setTimeout(callback, delay) {
    setTimeoutId++;
    setTimeouts[setTimeoutId] = callback;

    self.postMessage({type: "setTimeout", delay: delay, id: setTimeoutId});
  }
}

if (typeof module === "undefined") {
  module = {};
}


function sendMessages(messages) {
  self.postMessage({type: "messages", contents: messages});
}
