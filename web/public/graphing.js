$(function() {
    var ctx = $('#cpuUsage').get(0).getContext('2d');
    var new_labels = [];
    var random_data = [];
    var random_data_2 = [];
    var k = new Date(null);
    for(var i = 0; i < 24; i++) {
        new_labels[i] = k.toISOString().substr(11,8); 
        random_data[i] = Math.floor(Math.random() * 100); 
        random_data_2[i] = Math.floor(Math.random() * 100);
        k.setMinutes(60);
    }

    console.log(new_labels);

    new Chart(ctx, {
      type: 'line',
      data: {
        labels: new_labels,
        datasets: [{ 
            data: random_data,
            label: "Network Ingress",
            borderColor: "#c45850",
            fill: true
          },
          {
            data: random_data_2,
            label: "Network Egress",
            borderColor: "#111E6C",
            fill: true
          }
        ]
      },
      options: {
        title: {
          display: false,
          text: ''
        }
      }
    });
});
