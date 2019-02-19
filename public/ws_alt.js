$(document).ready(function() {

  if("WebSocket" in window){
      connect();
      function connect(){
          var socket;
          var host = $('.content').attr('ws-url');

          try {
              var socket = new WebSocket(host);

              message('<div class="direct-chat-text">Socket Status: '+socket.readyState);

              socket.onopen = function(){
             	 message('<div class="direct-chat-text">Socket Status: '+socket.readyState+' (open)');
              }

              socket.onmessage = function(msg){
                 var e = JSON.parse(msg.data);
                 if(e.event == "update") {
                     if(typeof(e.class) != "undefined") {
//             	        message('<div class="direct-chat-text">Updating class to: ' + e.class);
                        $('#' + e.id).removeClass();
                        $('#' + e.id).addClass(e.class);
                     }
                     else if(typeof(e.text) != "undefined") {
  //           	        message('<div class="direct-chat-text">Updating text to: ' + e.text);
                         $('#' + e.id).text(e.text);
                     }
                 }
                 else if(e.event == "tick") {
                     message('<div class="direct-chat-text">Tick!');
                 }
                 else if(e.event == "eval") {
                     console.log(e.data);
                     eval(e.data);
                 }
                 else if(e.event == "hello") {
                     message('<div class="direct-chat-text">Server began handshake process.');
                     var authObj = {"key": $('.content').attr('key'), "id": $('.content').attr('vps')};
                     socket.send(JSON.stringify(authObj));
                 }
                 else if(e.event == "timeout") {
                     message('<div class="direct-chat-text">Server closed connection due to authentication timeout.');
                 }
                 else if(e.event == "success_auth") {
                     message('<div class="direct-chat-text">Passed auth successfully.');
                 }
                 else if(e.event == "failed_auth") {
                     message('<div class="direct-chat-text">Failed auth? Contact sysadmin.');
                 }


              }

              socket.onclose = function(){
              	message('<div class="direct-chat-text">Socket Status: '+socket.readyState+' (Closed)');
              }			

          } catch(exception){
             message('<div class="direct-chat-text">Error'+exception);
          }

          function message(msg){
              outMsg = '<div class="direct-chat-msg">';
              outMsg = outMsg + '<div class="direct-chat-info clearfix"><span class="direct-chat-name pull-left">Server</span><span class="direct-chat-timestamp pull-right">' + new Date().toLocaleString() + '</span></div>';
              outMsg = outMsg + '<img class="direct-chat-img" src="https://cdn1.iconfinder.com/data/icons/nuvola2/128x128/filesystems/server.png"></img>' + msg;
              $('#messages').append(outMsg+'</div></div>');

              $('#messages').scrollTop = $('#messages').scrollHeight;
          }
            window.setInterval(function() {
              var elem = document.getElementById('messages');
              elem.scrollTop = elem.scrollHeight;
            }, 500);

          $('#vm-start').click(function(){
              var action = {event: "start"};
              socket.send(JSON.stringify(action));
          });
          $('#vm-restart').click(function(){
              var action = {event: "restart"};
              socket.send(JSON.stringify(action));
          });
          $('#vm-shutdown').click(function(){
              var action = {event: "shutdown"};
              socket.send(JSON.stringify(action));
          });



      }//End connect

  }//End else

});
