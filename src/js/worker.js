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
};

// Polyfill setTimeout
if (typeof setTimeout === "undefined") {
  function delayUntil(time, callback) {
    if (new Date().getTime() >= time) {
      callback();
    } else {
      self.thread.nextTick(function() { delayUntil(time, callback); });
    }
  }

  setTimeout = function setTimeout(callback, delay) {
    if (delay === 0) {
      self.thread.nextTick(callback);
    } else {
      delayUntil(new Date().getTime() + delay, callback);
    }
  }
}

if (typeof module === "undefined") {
  module = {};
}


function sendMessages(messages) {
  self.postMessage({type: "messages", contents: messages});
}
