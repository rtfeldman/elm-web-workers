var Supervisor = require("elm-web-workers");
var path = require("path");
var elmPath = path.join(__dirname, "Elm.js");
var http = require("http");

var supervisor = new Supervisor(elmPath, "Example");


supervisor.on("emit", function(msg) {
  console.log("[supervisor]:", msg);
});

supervisor.on("close", function(msg) {
  console.log("Closed with message:", msg);
});

supervisor.start();

supervisor.send({msgType: "echo", data: "Spawning some workers..."});
supervisor.send({msgType: "spawn", data: "5"});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});
supervisor.send({msgType: "spawn", data: "" + Math.random()});


setInterval(function() {
  console.log("sending echoViaWorker message to supervisor...")
  supervisor.send({msgType: "echoViaWorker", data: "5"});
  console.log("sent message to supervisor without crashing")
}, 2000);

// Spin up a server just to prevent exiting
http.createServer(function(request, response) { response.end(); }).listen(8090);
