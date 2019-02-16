onconnect = function(e) {
    var init = false;
    var port = e.ports[0];

    port.onmessage = function(k) { 
        var n = k.data;

        if(n.event == "init") {
            if(init) {
                console.log("tv is off");
            }
            else {
                init = true;
            }
        }
        console.log(k.data);
    }
    /*
    var socket;
    var host = "ws://localhost:1337/ws";

    try {
        socket = new WebSocket(host);

        socket.onopen = function(){
          port.postMessage({event: "open"});
        }

        socket.onmessage = function(msg){
          var e = JSON.parse(msg.data);
          port.postMessage(e);
        }

        socket.onclose = function(){
          port.postMessage({event: "close"});
        }			

    } catch(exception) {
        port.postMessage({event: "exception"});
    }
    */
}

