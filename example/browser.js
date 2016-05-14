var supervisor = new Supervisor("Elm.js", "Example");

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
