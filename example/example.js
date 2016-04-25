var Supervisor = require("elm-web-workers").Supervisor;
var path = require("path");
var elmPath = path.join(__dirname, "Elm.js");

var supervisor = new Supervisor(elmPath, "Example", {receiveMessage: null});


supervisor.on("emit", function(msg) {
  console.log("[supervisor]:", msg);
});

supervisor.on("close", function(msg) {
  console.log("Closed with message:", msg);
});

supervisor.start();

supervisor.send({msgType: "echo", data: "Spawning some workers..."});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});

process.stdin.resume();
process.stdin.setEncoding('utf8');

var util = require("util");

process.stdin.on("data", function (text) {
  var val = util.inspect(text);

  supervisor.send({msgType: "echo", data: val});

  if (text === "quit\n") {
    done();
  }
});

function done() {
  process.exit();
}

