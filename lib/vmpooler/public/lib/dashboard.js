var dashboard_data = {};
var dashboard_svg = {};
var date_from = new Date();

var running_data = {};
var weekly_data = {
  platform_count: {},
  clone_max: 0,
  clone_platform_max: 0,
  clone_count: [],
  clone_avg: [],
  boot_avg: []
};
var capacity_data = {};

var colorscale = d3.scale.category20();
var stack = d3.layout.stack().values(function(d) { return d.values; });



Date.prototype.yyyymmdd = function() {
  var yyyy = this.getFullYear().toString();
  var mm = (this.getMonth()+1).toString();
  var dd = this.getDate().toString();
  return yyyy + '-' + (mm[1] ? mm : '0' + mm[0]) + '-' + (dd[1] ? dd : '0' + dd[0]);
};



var data_url = {
  'capacity': '/dashboard/stats/vmpooler/pool',
  'pools'   : '/api/v1/vm',
  'running' : '/dashboard/stats/vmpooler/running',
  'status'  : '/api/v1/status',
  'summary' : '/api/v1/summary'
};



//--------------------------------------------------------------------
// Everything below this line will be updated in-browser via tick();
//--------------------------------------------------------------------

(function tick() { setTimeout(function() { // <self-update>

// Update "today's" date

date_from.setDate(date_from.getDate() - 6);

// Gather up data from multiple endpoints

$.each([
  'capacity',
  'pools',
  'running',
  'status',
  'summary'
], function(index, value) {
  dashboard_data[value] = (function() {
    var dashboard_data__live = null;

    var url = data_url[value];

    // Get history if this is the first tick() iteration

    switch (value) {
      case 'capacity': if (! dashboard_data[value]) { url += ('?history=1'); }; break;
      case 'running' : if (! dashboard_data[value]) { url += ('?history=1'); }; break;
      case 'summary' : if (! dashboard_data[value]) { url += ('?from=' + date_from.yyyymmdd()); }; break;
    }

    $.ajax({
      'url': url,
      'async': false,
      'global': false,
      'dataType': 'json',
      'success': function(data) {
        dashboard_data__live = data;
      }
    });

    return dashboard_data__live;
  })();
});

// Create an array of pool_maj

dashboard_data['tmp'] = {};
dashboard_data['pools_maj'] = [];
dashboard_data['pools'].sort().map(function(pool) {
  var pool_maj = pool.split('-', 2)[0];

  if (! dashboard_data['tmp'][pool_maj]) {
    dashboard_data['pools_maj'].push(pool_maj);
    dashboard_data['tmp'][pool_maj] = 1;
  }
});
delete dashboard_data['tmp'];

// Create a color swatch for each pool_maj

dashboard_data['color'] = {};
dashboard_data['tmp'] = 0;
dashboard_data['pools_maj'].sort().map(function(pool_maj) {
  dashboard_data['color'][pool_maj] = colorscale(dashboard_data['tmp']);
  dashboard_data['tmp']++;
});
delete dashboard_data['tmp'];



// #dashboard-numbers
// Numerical metrics (# cloning, running, ready, waiting, etc.)

$('#dashboard-numbers').empty();

var numbers_width = parseInt(d3.select('.col-md-2').style('width')) / 2;
var numbers_height = 75;
var numbers_data = {
  label: {
    'clone_total': 'cloned today',
    'clone_average': 'clone time avg',
    'capacity': 'capacity pct',
    'total': 'total # of VMs',
    'ready': 'ready & waiting',
    'cloning': 'being cloned',
    'booting': 'booting up',
    'running': 'running tests',
    'completed': 'waiting to die'
  },
  key: {
    'clone_total': dashboard_data['status']['clone']['count']['total'],
    'clone_average': dashboard_data['status']['clone']['duration']['average'] + 's',
    'capacity': dashboard_data['status']['capacity']['percent'],
    'total': dashboard_data['status']['queue']['total'],
    'ready': dashboard_data['status']['queue']['ready'],
    'cloning': dashboard_data['status']['queue']['cloning'],
    'booting': dashboard_data['status']['queue']['booting'],
    'running': dashboard_data['status']['queue']['running'],
    'completed': dashboard_data['status']['queue']['completed']
  }
};

$.each([
  'clone_total',
  'clone_average',
  'capacity',
  'total',
  'ready',
  'cloning',
  'booting',
  'running',
  'completed'
], function(index, value) {
  dashboard_svg[value] = d3.select('#dashboard-numbers')
    .append('svg')
    .style('float', 'right')
    .attr('class', 'col-md-1')
    .attr('height', numbers_height);

  dashboard_svg[value]
    .append('text')
      .text(
        (numbers_data['label'][value])
     )
      .attr({
        'text-anchor': 'end',
        'x': numbers_width - 5,
        'y': '50',
        'font-face': '\'PT Sans\', sans-serif',
        'font-size': '12px',
        'font-weight': 'bold',
        'fill': '#666'
      });


  dashboard_svg[value]
    .append('text')
      .text(
        (numbers_data['key'][value])
     )
      .attr({
        'text-anchor': 'end',
        'x': numbers_width - 5,
        'y': '36',
        'font-face': '\'PT Sans\', sans-serif',
        'font-weight': 'bold',
        'font-size': '40px',
        'letter-spacing': '-0.025em',
        'fill': '#444'
      });
});

numbers_data = null;



// #dashboard-running
// By-platform graph of what's been running for the past hour; includes pool_maj legend

$('#dashboard-running').empty();

var running_width = parseInt(d3.select('.col-md-10').style('width'));
var running_height = 160;

if (! running_data['stack']) {
  running_data['stack'] = [];
}

// Process 'running' history

dashboard_data['pools_maj'].sort().map(function(pool_maj) {
  if (dashboard_data['running'][pool_maj]['history']) {
    for (var c = 0; c < dashboard_data['running'][pool_maj]['history'].length; c++) {
      if (! running_data['stack'][c]) {
        running_data['stack'][c] = {};
      }

      running_data['stack'][c][pool_maj] = dashboard_data['running'][pool_maj]['history'][c];
    }
  }
});

if (! running_data['graph']) {
  running_data['tmp'] = [];
  for (var metric in running_data['stack']) {
    for (var c = 0; c < 8; c++) {
      running_data['tmp'].push(running_data['stack'][metric]);
    }
  }
  running_data['stack'] = running_data['tmp'];
  delete running_data['tmp'];
}

// Process 'running' newest values and add them to the stack

dashboard_data['tmp'] = {};
for (var key in dashboard_data['running']) {
  dashboard_data['tmp'][key] = dashboard_data['running'][key]['running'];
}

running_data['stack'].push(dashboard_data['tmp']);
delete dashboard_data['tmp'];

// Calculate 'running' graph stack

running_data['graph'] = stack(
  dashboard_data['pools_maj'].sort().map(function(pool_maj) {
    return {
      name: pool_maj,
      values: running_data['stack'].map(function(d) {
        return { y: d[pool_maj] };
      })
    }
  })
);

// Calculate 'running' graph shapes

running_data['total'] = d3.max(
  running_data['graph'], function(layer) {
    return d3.max(layer.values, function(d) {
      return d.y0 + d.y;
    });
  }
);

var running_x = d3.scale.linear().domain([0, 500]).range([5, running_width - 20]);
var running_y = d3.scale.linear().domain([0, running_data['total']]).range([running_height, 0]);

var running_area = d3.svg.area()
  .x(function(d, i) { return running_x(i); })
  .y0(function(d) { return running_y(d.y0); })
  .y1(function(d) { return running_y(d.y0 + d.y); });

// The 'running' SVG

var running_graph = d3.select('#dashboard-running')
  .append('svg')
  .attr('height', running_height)
  .attr('class', 'col-md-10')
  .append('g');

dashboard_svg['running'] = running_graph.selectAll('#dashboard-running')
  .data(running_data['graph'])
  .enter()
  .append('g');

// A texture
defs = dashboard_svg['running'].append('svg:defs');

defs.append('svg:pattern')
  .attr('id', 'background')
  .attr('patternUnits', 'userSpaceOnUse')
  .attr('width', '500px')
  .attr('height', '500px')
  .append('svg:image')
    .attr('xlink:href', '/img/textured_paper.png')
    .attr('x', 0)
    .attr('y', 0)
    .attr('width', '500px')
    .attr('height', '500px');

dashboard_svg['running'] 
  .append('path')
    .attr('class', 'area')
    .attr('d', function(d) { return running_area(d.values); })
    .attr('opacity', '0.75')
    .style('fill', 'url(#background)');

dashboard_svg['running']
  .append('path')
    .attr('class', 'area')
    .attr('d', function(d) { return running_area(d.values); })
    .attr('opacity', '0.5')
    .style('fill', function(d) { return dashboard_data['color'][d.name]; });

// Legend

dashboard_data['pools_maj'].sort().map(function(pool_maj) {
  dashboard_svg['legend' + pool_maj] = d3.select('#dashboard-running')
    .append('svg')
    .attr('class', 'col-md-1')
    .attr('height', '20px');

  dashboard_svg['legend' + pool_maj]
    .append('rect')
      .attr({
        'x': '5',
        'y': '5',
        'width': '10',
        'height': '10',
        'opacity': '0.75',
        'fill': 'url(#background)'
      });

  dashboard_svg['legend' + pool_maj]
    .append('rect')
      .attr({
        'x': '5',
        'y': '5',
        'width': '10',
        'height': '10',
        'opacity': '0.5',
        'fill': function(d) { return dashboard_data['color'][pool_maj]; }
      });

  dashboard_svg['legend' + pool_maj]
    .append('text')
      .text(
        (pool_maj)
     )
      .attr({
        'x': '20',
        'y': '15',
        'font-face': '\'PT Sans\', sans-serif',
        'font-size': '12px',
        'font-weight': 'bold',
        'fill': '#666'
      });
  }
);

if (running_data['stack'].length > 500) {
  running_data['stack'].shift();
}



// #dashboard-weekly
// Weekly graphs (daily clone count, clone/boot avgs, etc.)

$('#dashboard-weekly').empty();

var weekly_width = (parseInt(d3.select('.col-md-2').style('width')) * 2) - 10;
var weekly_height = 100;

// Update based on if it's a new day, first tick() iteration, or neither

if (dashboard_data['summary']['daily'].length == 1) {
  weekly_data['clone_count'].pop();
  weekly_data['clone_avg'].pop();
  weekly_data['boot_avg'].pop();
}
else if (dashboard_data['summary']['daily'].length == 7) {
  weekly_data['clone_count'] = [];
  weekly_data['clone_avg'] = [];
  weekly_data['boot_avg'] = [];
  weekly_data['platform_count'] = {};
}

dashboard_data['summary']['daily'].sort().map(function(day) {
  weekly_data['clone_count'].push(day['clone']['count']['total']);
  weekly_data['clone_avg'].push(day['clone']['duration']['average']);
  weekly_data['boot_avg'].push(day['boot']['duration']['average']);

  if (day['clone']['count']['total'] > weekly_data['clone_max']) {
    weekly_data['clone_max'] = day['clone']['count']['total'];
  }
});

// Consolidate clone totals into pool_maj groups

dashboard_data['pools'].sort().map(function(pool) {
  var pool_maj = pool.split('-', 2)[0];

  if (! weekly_data['platform_count'][pool_maj]) {
    weekly_data['platform_count'][pool_maj] = 0;
  }

  if (dashboard_data['summary']['clone']['count']['pool'][pool]) {
    weekly_data['platform_count'][pool_maj] += dashboard_data['summary']['clone']['count']['pool'][pool]['total'];
  }
});

dashboard_data['pools_maj'].sort().map(function(pool_maj) {
  if (weekly_data['platform_count'][pool_maj] > weekly_data['clone_platform_max']) {
    weekly_data['clone_platform_max'] = weekly_data['platform_count'][pool_maj];
  }
});

var weekly_x = d3.scale.linear().domain([0, 6]).range([0, weekly_width]);
var weekly_y_clone_count = d3.scale.linear().domain([0, weekly_data['clone_max']]).range([weekly_height, 0]);
var weekly_y_boot_avg = d3.scale.linear().domain([0, Math.max.apply(Math, weekly_data['boot_avg'])]).range([weekly_height, 0]);
var weekly_y_platform_count = d3.scale.linear().domain([0, weekly_data['clone_platform_max']]).range([weekly_height, 0]);

var area_clone_count = d3.svg.area()
  .interpolate('linear')
  .x(function(d, i) { return weekly_x(i); })
  .y0(weekly_height)
  .y1(function(d) { return weekly_y_clone_count(d); });

var area_boot_avg = d3.svg.area()
  .interpolate('linear')
  .x(function(d, i) { return weekly_x(i); })
  .y0(weekly_height)
  .y1(function(d) { return weekly_y_boot_avg(d); });

// Create some SVGs

for (graph in graphs = ['clone_count', 'clone_boot_avg']) {
  dashboard_svg[graphs[graph]] = d3.select('#dashboard-weekly')
    .append('svg')
      .attr('class', 'col-md-4')
      .attr('height', weekly_height);

  dashboard_svg[graphs[graph]]
    .append('g')
    .attr('class', 'x tick')
    .attr('transform', 'translate(0,' + (weekly_height) + ')')
    .call(
      d3.svg.axis()
        .scale(weekly_x)
        .ticks(7)
        .tickSize(-weekly_height)
        .outerTickSize(0)
        .tickFormat('')
        .tickSubdivide(true)
        .orient('bottom')
   );
}

dashboard_svg['platform_count'] = d3.select('#dashboard-weekly')
  .append('svg')
    .attr('class', 'col-md-4')
    .attr('height', weekly_height);

dashboard_svg['platform_count']
  .append('g')
  .attr('class', 'x tick')
  .attr('transform', 'translate(0,' + (weekly_height) + ')')
  .call(
    d3.svg.axis()
      .scale(weekly_x)
      .ticks(0)
      .tickSize(-weekly_height)
      .orient('bottom')
 );

// Area shapes for clone_count and clone/boot time avgs

var area_clone_count = d3.svg.area()
  .interpolate('linear')
  .x(function(d, i) { return weekly_x(i); })
  .y0(weekly_height)
  .y1(function(d) { return weekly_y_clone_count(d); });

var area_boot_avg = d3.svg.area()
  .interpolate('linear')
  .x(function(d, i) { return weekly_x(i); })
  .y0(weekly_height)
  .y1(function(d) { return weekly_y_boot_avg(d); });

dashboard_svg['clone_count']
  .append('path')
    .attr({
      'class': 'area',
      'fill': 'url(#background)',
      'opacity': '0.75',
      'd': area_clone_count(weekly_data['clone_count'])
    });

dashboard_svg['clone_count']
  .append('path')
    .attr({
      'class': 'area',
      'fill': 'seagreen',
      'opacity': '0.5',
      'd': area_clone_count(weekly_data['clone_count'])
    });

dashboard_svg['clone_boot_avg']
  .append('path')
    .attr({
      'class': 'area',
      'fill': 'url(#background)',
      'opacity': '0.75',
      'd': area_boot_avg(weekly_data['boot_avg'])
    });

dashboard_svg['clone_boot_avg']
  .append('path')
    .attr({
      'class': 'area',
      'fill': 'crimson',
      'opacity': '0.5',
      'd': area_boot_avg(weekly_data['boot_avg'])
    });

dashboard_svg['clone_boot_avg']
  .append('path')
    .attr({
      'class': 'area',
      'fill': 'gold',
      'opacity': '0.75',
      'd': area_boot_avg(weekly_data['clone_avg'])
    });

// Add a bar to the platform_count raph for each pool_maj

dashboard_data['tmp'] = 0;
dashboard_data['pools_maj'].sort().map(function(pool_maj) {
  var x = dashboard_data['tmp'] * (weekly_width / dashboard_data['pools_maj'].length);
  var y = weekly_y_platform_count(weekly_data['platform_count'][pool_maj]) - 1;
  var width = weekly_width / dashboard_data['pools_maj'].length;

  if (y == -1) { y = 0; }

  dashboard_svg['platform_count']
    .append('rect')
      .attr({
        'x': x,
        'y': y,
        'width': width,
        'height': weekly_height,
        'fill': 'url(#background)',
        'opacity': '0.75'
      });

  dashboard_svg['platform_count']
    .append('rect')
      .attr({
        'x': x,
        'y': y,
        'width': width,
        'height': weekly_height,
        'fill': function(d) { return dashboard_data['color'][pool_maj]; },
        'opacity': '0.5'
      });

  dashboard_data['tmp']++;
});
delete dashboard_data['tmp'];



// #dashboard-pool
// Many little graphs showing individual pool capacities

$('#dashboard-pool').empty();

var capacity_col_class = 'col-md-2';
var capacity_width = parseInt(d3.select('.col-md-2').style('width'));
var capacity_height = 47;

if (capacity_width > 250) {
  capacity_col_class = 'col-md-1';
  capacity_width = parseInt(d3.select('.col-md-1').style('width'));
}

dashboard_data['pools'].sort().map(function(pool) {
  var capacity_x = d3.scale.linear().domain([0, 500]).range([5, capacity_width - 5]);
  var capacity_y = d3.scale.linear().domain([dashboard_data['capacity'][pool]['size'], 0]).range([0, capacity_height - 15]);

  var capacity_area = d3.svg.area()
    .interpolate('basis')
    .x(function(d, i) { return capacity_x(i); })
    .y0(capacity_height - 15)
    .y1(function(d) { return capacity_y(d); });

  var capacity_path = d3.svg.line()
    .interpolate('basis')
    .x(function(d, i) { return capacity_x(i); })
    .y(function(d) { return capacity_y(d); });

  if (! capacity_data[pool]) {
    capacity_data[pool] = {};
  }

  if (! capacity_data[pool]['r']) {
    capacity_data[pool]['r'] = [];
  }

  // Process 'capacity' history

  if (dashboard_data['capacity'][pool]['history']) {
    capacity_data[pool]['r'] = dashboard_data['capacity'][pool]['history'];
  }

  capacity_data[pool]['r'].push(dashboard_data['capacity'][pool]['ready']);

  var capacity_current = capacity_data[pool]['r'].slice(-1)[0];
  var capacity_size    = dashboard_data['capacity'][pool]['size'];
  var capacity_pct     = Math.floor((capacity_current / capacity_size) * 100);

  var statuscolor = '#78a830';
  if (capacity_pct < 50) { statuscolor = '#f0a800'; }
  if (capacity_pct < 25) { statuscolor = '#d84830'; }

  // Define 'capacity' SVG

  dashboard_svg['capacity' + pool] = d3.select('#dashboard-pool')
    .append('svg')
      .attr('class', capacity_col_class)
      .attr('height', capacity_height);

  dashboard_svg['capacity' + pool]
    .append('g')
    .attr('class', 'x tick')
    .attr('transform', 'translate(0,' + (capacity_height - 15) + ')')
    .call(
      d3.svg.axis()
        .scale(capacity_x)
        .ticks(4)
        .tickSize(-capacity_height)
        .outerTickSize(0)
        .tickFormat('')
        .tickSubdivide(true)
        .orient('bottom')
   );

  // Draw 'capacity' path

  dashboard_svg['capacity' + pool]
    .append('path')
      .attr('class', 'area')
      .attr('fill', 'url(#background)')
      .attr('opacity', '0.75')
      .attr('d', capacity_area(capacity_data[pool]['r']));

  dashboard_svg['capacity' + pool]
    .append('path')
      .attr('class', 'area')
      .attr('fill', statuscolor)
      .attr('opacity', '0.5')
      .attr('d', capacity_area(capacity_data[pool]['r']));

  dashboard_svg['capacity' + pool]
    .append('path')
      .attr('class', 'line')
      .attr('stroke', statuscolor)
      .attr('stroke-width', '1')
      .attr('d', capacity_path(capacity_data[pool]['r']));

  // Add labels to 'capacity' graphs

  dashboard_svg['capacity' + pool]
    .append('text')
      .text(
        (pool)
     )
      .attr({
        'x': '10',
        'y': capacity_height - 33,
        'font-face': '\'PT Sans\', sans-serif',
        'font-weight': 'bold',
        'font-size': '12px',
        'fill': '#444'
      });

  dashboard_svg['capacity' + pool]
    .append('text')
      .text(
        (capacity_pct + '%')
     )
      .attr({
        'x': '10',
        'y': capacity_height - 20,
        'font-face': '\'PT Sans\', sans-serif',
        'font-size': '12px',
        'letter-spacing': '-0.05em',
        'fill': '#444'
      });

  dashboard_svg['capacity' + pool]
    .append('text')
      .text(
        ('(') +
        (capacity_current) +
        ('/') +
        (capacity_size) +
        (')')
     )
      .attr({
        'x': 45,
        'y': capacity_height - 20,
        'font-face': '\'PT Sans\', sans-serif',
        'font-size': '12px',
        'letter-spacing': '-0.05em',
        'fill': '#444'
      });



  if (capacity_data[pool]['r'].length > 500) {
    capacity_data[pool]['r'].shift();
  }
});



// Hide the 'loading' screen

$('#loading').hide();

// Refresh!

tick(); }, 5000); })(); // </self-update>
