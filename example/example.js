var Supervisor = require("elm-web-workers");
var path = require("path");
var elmPath = path.join(__dirname, "Elm.js");

var supervisor = new Supervisor(elmPath, "Example");

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
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "5"});


setInterval(function() {
  supervisor.send({msgType: "echoViaWorker", data: "5"});
}, 2000);
