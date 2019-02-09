$(function() {
    var ctx_2 = $('#networkIo').get(0).getContext('2d');
    var ctx = $('#cpuUsage').get(0).getContext('2d');
    var new_labels = [];
    var random_data = [];
    var random_data_2 = [];
    var k = new Date(null);
    for(var i = 0; i < 25; i++) {
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
            label: "CPU Usage",
            borderColor: "#c45850",
            fill: true
          }
        ]
      },
      options: {
        animation: false,
        tooltips: {
            callbacks: {
              label: function(tooltipItem, data) {
                var label = data.datasets[tooltipItem.datasetIndex].data[tooltipItem.index];
                return 'Usage: ' + label + '%';
              }
            }
        },
        title: {
          display: false,
          text: ''
        }
      }
    });

    new Chart(ctx_2, {
      type: 'line',
      data: {
        labels: new_labels,
        datasets: [{ 
            data: random_data,
            label: "Ingress",
            borderColor: "#c45850",
            fill: true
          },
          {
            data: random_data_2,
            label: "Egress",
            borderColor: "#111E6C",
            fill: true
          }
        ]
      },
      options: {
        scales: {
            yAxes: [{
                ticks: {
                   min: 0,
                   max: 100,
                   callback: function(value){return value+ " kbps"}
                },  
                scaleLabel: {
                   display: true,
                   labelString: "Throughput"
                }
            }]
        },
        animation: false,
        tooltips: {
            callbacks: {
              label: function(tooltipItem, data) {
                var label = data.datasets[tooltipItem.datasetIndex].data[tooltipItem.index];
                console.log(data.datasets[tooltipItem.datasetIndex].label);
                return data.datasets[tooltipItem.datasetIndex].label + ': ' + label + ' kbps';
              }
            }
        },
        title: {
          display: false,
          text: ''
        }
      }
    });

});
