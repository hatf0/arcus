$(function() {
//  var ctx = $('#cpuUsage').get(0).getContext('2d');
//  var ctx2 = $('#diskUsage').get(0).getContext('2d');
  var ctx3 = $('#networkUsage').get(0).getContext('2d');
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

  
  /*
  new Chart(ctx, {
    type: 'doughnut',
    data: {
      datasets: [{
        data: ["50", "100", "20"],
        backgroundColor: ["#3e95cd", "#8e5ea2","#3cba9f"]
      }],

      labels: [
        "node-1",
        "node-2",
        "node-3"
      ]
    },
    options: {
      legend: {
            display: false
      },
      tooltips: {
        callbacks: {
          label: function(tooltipItem, data) {
            var label = data.datasets[tooltipItem.datasetIndex].data[tooltipItem.index];
            return data.labels[tooltipItem.index] + ': ' + label + '%';
          }
        }
      },
      elements: {
        center: {
          text: '99%',
          color: '#36A2EB', //Default black
          fontStyle: 'Arial', //Default Arial
          sidePadding: 50 //Default 20 (as a percentage)
        }
      }
    }
  });
  new Chart(ctx2, {
    type: 'doughnut',
    data: {
      datasets: [{
        data: ["50", "100", "20"],
        backgroundColor: ["#3e95cd", "#8e5ea2","#3cba9f"]
      }],

      labels: [
        "node-1",
        "node-2",
        "node-3"
      ]
    },
    options: {
      legend: {
            display: false
      },
      tooltips: {
        callbacks: {
          label: function(tooltipItem, data) {
            var label = data.datasets[tooltipItem.datasetIndex].data[tooltipItem.index];
            return data.labels[tooltipItem.index] + ': ' + label + ' gb';
          }
        }
      },
      elements: {
        center: {
          text: '99%',
          color: '#36A2EB', //Default black
          fontStyle: 'Arial', //Default Arial
          sidePadding: 50 //Default 20 (as a percentage)
        }
      }
    }
  });
*/
  new Chart(ctx3, {
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
})
