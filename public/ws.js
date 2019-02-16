$(document).ready(function() {

  if("WebSocket" in window) {
      if(!!window.SharedWorker) {
          var ws_worker = new SharedWorker("http://localhost:8080/static/ws_worker.js");
          ws_worker.port.onmessage = function(e) {
              console.log(e.data);
          }

          ws_worker.port.postMessage({event: "init", data: ["ws://localhost:1337/ws", $('.content').attr('key'), $('.content').attr('vps')]});
      }
  }

});
