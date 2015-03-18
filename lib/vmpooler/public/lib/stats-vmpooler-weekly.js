Date.prototype.yyyymmdd = function() {
  var yyyy = this.getFullYear().toString();
  var mm = (this.getMonth()+1).toString();
  var dd = this.getDate().toString();
  return yyyy + '-' + ( mm[1] ? mm : '0' + mm[0] ) + '-' + ( dd[1] ? dd : '0' + dd[0] );
};

var date_from = new Date();
date_from.setDate( date_from.getDate() - 6 );

var clone_weekly_url = '/summary?from=' + date_from.yyyymmdd();
var clone_weekly_height = 160;

var colorscale = d3.scale.category20();
var color = {};

var stats_vmpooler_weekly__data  = {};
var stats_vmpooler_weekly__svg   = {};

d3.json( clone_weekly_url,

  function( stats_vmpooler_weekly__data ) {

    var stats_vmpooler_weekly__data__live = ( function() {
      var stats_vmpooler_weekly__data__live = null;

      $.ajax( {
        'url': clone_weekly_url,
        'async': false,
        'global': false,
        'dataType': 'json',
        'success': function( data ) {
          stats_vmpooler_weekly__data__live = data;
        }
      } );

      return stats_vmpooler_weekly__data__live;
    } )();

    var clone_weekly_width = document.getElementById( 'stats-vmpooler-weekly-clone-count-pool' ).offsetWidth - 25;

    // Empty the divs
    $( '#stats-vmpooler-weekly-clone-count-pool' ).empty();
    $( '#stats-vmpooler-weekly-daily' ).empty();

    // Per-pool clone count bar graph
    stats_vmpooler_weekly__svg[ 'clone_count__pool' ] = d3.select( '#stats-vmpooler-weekly-clone-count-pool' )
      .append( 'svg' )
        .style( 'margin', '-40px 0px 10px 0px' )
        .style( 'border-bottom', 'solid 1px #888' )
        .attr( {
          'width': clone_weekly_width,
          'height': clone_weekly_height
        } );

    // Define a background texture to apply to SVGs
    defs = stats_vmpooler_weekly__svg[ 'clone_count__pool' ].append( 'svg:defs' );

    defs.append( 'svg:pattern' )
      .attr( {
        'id': 'background',
        'patternUnits': 'userSpaceOnUse',
        'width': '500px',
        'height': '500px'
      } )
      .append( 'svg:image' )
        .attr( {
          'xlink:href': '/img/textured_paper.png',
          'x': 0,
          'y': 0,
          'width': '500px',
          'height': '500px'
      } );


    stats_vmpooler_weekly__data[ 'clone_count__max' ] = 0
    stats_vmpooler_weekly__data[ 'pool_maj__count' ] = 0

    Object.keys( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ] ).sort().map(
      function( pool ) {

        // Determine 'major' pool (eg. 'centos' for 'centos-6-x86_64')
        var pool_maj = 'unknown';
        if ( pool.match( /^(.+?)\-/ ) ) { pool_maj = pool.match( /^(.+?)\-/ )[ 1 ]; }

        // Generate fill color for pool_maj
        if ( ! color[ pool_maj ] ) {
          color[ pool_maj ] = colorscale( stats_vmpooler_weekly__data[ 'pool_maj__count' ] );
          stats_vmpooler_weekly__data[ 'pool_maj__count' ]++;
        }

        // Is this the most clones?
        if ( parseInt( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ][ pool ][ 'total' ] ) > stats_vmpooler_weekly__data[ 'clone_count__max' ] ) {
          stats_vmpooler_weekly__data[ 'clone_count__max' ] = parseInt( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ][ pool ][ 'total' ] )
        }
 
      }
    );

    // Set up dynamic x and y domain scales
    stats_vmpooler_weekly__data[ 'y__clone_count__pool' ] = d3.scale.linear().domain( [ 0, stats_vmpooler_weekly__data[ 'clone_count__max' ] ] ).range( [ clone_weekly_height, 0 ] );
    stats_vmpooler_weekly__data[ 'pool__count' ] = 0;

    Object.keys( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ] ).sort().map(
      function( pool ) {

        // Determine 'major' pool (eg. 'centos' for 'centos-6-x86_64')
        var pool_maj = 'unknown';
        if ( pool.match( /^(.+?)\-/ ) ) { pool_maj = pool.match( /^(.+?)\-/ )[ 1 ]; }

        // Append a bar to the per-pool clone count bar graph
        stats_vmpooler_weekly__svg[ 'clone_count__pool' ]
          .append( 'rect' )
            .attr( {
              'x': stats_vmpooler_weekly__data[ 'pool__count' ] * ( clone_weekly_width / Object.keys( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ] ).length ),
              'y': stats_vmpooler_weekly__data[ 'y__clone_count__pool' ]( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ][ pool ][ 'total' ] ),
              'width': ( clone_weekly_width / Object.keys( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ] ).length ) - 2,
              'height': clone_weekly_height,
              'fill': color[ pool_maj ],
              'opacity': '0.75'
            } );

        stats_vmpooler_weekly__svg[ 'clone_count__pool' ]
          .append( 'rect' )
            .attr( {
              'x': stats_vmpooler_weekly__data[ 'pool__count' ] * ( clone_weekly_width / Object.keys( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ] ).length ),
              'y': stats_vmpooler_weekly__data[ 'y__clone_count__pool' ]( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ][ pool ][ 'total' ] ),
              'width': ( clone_weekly_width / Object.keys( stats_vmpooler_weekly__data__live[ 'clone' ][ 'count' ][ 'pool' ] ).length ) - 2,
              'height': clone_weekly_height,
              'fill': 'url( #background )',
              'opacity': '0.50'
            } );

        // Append a key to the per-pool clone count bar graph
        if ( ! stats_vmpooler_weekly__svg[ 'clone_count__pool__key__' + pool_maj ] ) {
          stats_vmpooler_weekly__svg[ 'clone_count__pool__key__' + pool_maj ] = d3.select( '#stats-vmpooler-weekly-clone-count-pool' )
            .append( 'svg' )
              .style( 'padding', '0px 10px 10px 10px' )
              .attr( {
                'width': '130px',
                'height': '12px'
              } );

          stats_vmpooler_weekly__svg[ 'clone_count__pool__key__' + pool_maj ]
            .append( 'rect' )
              .attr( {
                'x': '5',
                'y': '3',
                'width': '10',
                'height': '10',
                'fill': color[ pool_maj ],
                'opacity': '0.75'
              } );

          stats_vmpooler_weekly__svg[ 'clone_count__pool__key__' + pool_maj ]
            .append( 'rect' )
              .attr( {
                'x': '5',
                'y': '3',
                'width': '10',
                'height': '10',
                'fill': 'url( #background )',
                'opacity': '0.50'
              } );

          stats_vmpooler_weekly__svg[ 'clone_count__pool__key__' + pool_maj ]
            .append( 'text' )
              .text(
                ( pool_maj )
              )
              .attr( {
                'x': '20',
                'y': '12',
                'font-face': '\'PT Sans\', sans-serif',
                'font-size': '12px',
                'font-weight': 'bold',
                'fill': '#888'
              } );
        }

        stats_vmpooler_weekly__data[ 'pool__count' ]++;

      }
    );

//
    // Daily clone count, clone average, and boot average graphs
    for ( graph in graphs = [ 'clone_count__day', 'clone_avg__day', 'boot_avg__day' ] ) {
      stats_vmpooler_weekly__svg[ graphs[ graph ] ] = d3.select( '#stats-vmpooler-weekly-daily' )
        .append( 'svg' )
          .style( 'margin', '20px 0px 0px 0px' )
          .style( 'padding', '0px 25px 25px 0px' )
          .style( 'float', 'left' )
          .attr( 'width', ( clone_weekly_width / 3 ) - 20 )
          .attr( 'height', clone_weekly_height );

      stats_vmpooler_weekly__svg[ graphs[ graph ] ]
        .append( 'g' )
        .attr( 'class', 'x tick' )
        .attr( 'transform', 'translate( 0,' + ( clone_weekly_height ) + ')' )
        .call(
          d3.svg.axis()
            .scale( d3.scale.linear().domain( [ 0, 6 ] ).range( [ 0, ( clone_weekly_width / 3 ) - 20 ] ) )
            .ticks( 7 )
            .tickSize( -clone_weekly_height )
            .outerTickSize( 0 )
            .tickFormat( '' )
            .tickSubdivide( true )
            .orient( 'bottom' )
        );
    }
//
    stats_vmpooler_weekly__data[ 'clone_total' ] = [];
    stats_vmpooler_weekly__data[ 'clone_avg' ] = [];
    stats_vmpooler_weekly__data[ 'boot_avg' ] = [];

    stats_vmpooler_weekly__data[ 'clone_max' ] = 0;

    stats_vmpooler_weekly__data__live[ 'daily' ].sort().map(
      function( day ) {
        stats_vmpooler_weekly__data[ 'clone_total' ].push( parseInt( day[ 'clone' ][ 'count' ][ 'total' ] ) );
        stats_vmpooler_weekly__data[ 'clone_avg' ].push( day[ 'clone' ][ 'duration' ][ 'average' ] );
        stats_vmpooler_weekly__data[ 'boot_avg' ].push( day[ 'boot' ][ 'duration' ][ 'average' ] );

        if ( parseInt( day[ 'clone' ][ 'count' ][ 'total' ] ) > stats_vmpooler_weekly__data[ 'clone_max' ] ) {
          stats_vmpooler_weekly__data[ 'clone_max' ] = parseInt( day[ 'clone' ][ 'count' ][ 'total' ] )
        }
      }
    );

    var x = d3.scale.linear().domain( [ 0, 6 ] ).range( [ 0, ( clone_weekly_width / 3 ) - 20 ] );

    var y_clone_total = d3.scale.linear().domain( [ 0, stats_vmpooler_weekly__data[ 'clone' ][ 'count' ][ 'max' ] ] ).range( [ clone_weekly_height, 0 ] );
    var y_clone_avg = d3.scale.linear().domain( [ 0, Math.max.apply( Math, stats_vmpooler_weekly__data[ 'clone_avg' ] ) ] ).range( [ clone_weekly_height, 0 ] );
    var y_boot_avg = d3.scale.linear().domain( [ 0, Math.max.apply( Math, stats_vmpooler_weekly__data[ 'boot_avg' ] ) ] ).range( [ clone_weekly_height, 0 ] ); 

    var area_clone_total = d3.svg.area()
      .interpolate( 'linear' )
      .x( function( d, i ) { return x( i ); } )
      .y0( clone_weekly_height )
      .y1( function( d ) { return y_clone_total( d ); } );

    var area_clone_avg = d3.svg.area()
      .interpolate( 'linear' )
      .x( function( d, i ) { return x( i ); } )
      .y0( clone_weekly_height )
      .y1( function( d ) { return y_clone_avg( d ); } );

    var area_boot_avg = d3.svg.area()
      .interpolate( 'linear' )
      .x( function( d, i ) { return x( i ); } )
      .y0( clone_weekly_height )
      .y1( function( d ) { return y_boot_avg( d ); } );

    stats_vmpooler_weekly__svg[ 'clone_count__day' ]
      .append( 'path' )
        .attr( {
          'class': 'area',
          'fill': 'seagreen',
          'opacity': '0.75',
          'd': area_clone_total( stats_vmpooler_weekly__data[ 'clone_total' ] )
        } );

    stats_vmpooler_weekly__svg[ 'clone_count__day' ]
      .append( 'path' )
        .attr( {
          'class': 'area',
          'fill': 'url( #background )',
          'opacity': '0.50',
          'd': area_clone_total( stats_vmpooler_weekly__data[ 'clone_total' ] )
        } );

    stats_vmpooler_weekly__svg[ 'clone_count__day' ]
      .append( 'text' )
        .text(
          ( 'daily provision count' )
        )
        .attr( {
          'x': '5',
          'y': clone_weekly_height + 20,
          'font-face': '\'PT Sans\', sans-serif',
          'font-weight': 'bold',
          'font-size': '12px',
          'fill': '#888'
        } );

    stats_vmpooler_weekly__svg[ 'clone_avg__day' ]
      .append( 'path' )
        .attr( {
          'class': 'area',
          'fill': 'steelblue',
          'opacity': '0.75',
          'd': area_clone_avg( stats_vmpooler_weekly__data[ 'clone_avg' ] )
        } );

    stats_vmpooler_weekly__svg[ 'clone_avg__day' ]
      .append( 'path' )
        .attr( {
          'class': 'area',
          'fill': 'url( #background )',
          'opacity': '0.50',
          'd': area_clone_avg( stats_vmpooler_weekly__data[ 'clone_avg' ] )
        } );

    stats_vmpooler_weekly__svg[ 'clone_avg__day' ]
      .append( 'text' )
        .text(
          ( 'clone time ( average )' )
        )
        .attr( {
          'x': '5',
          'y': clone_weekly_height + 20,
          'font-face': '\'PT Sans\', sans-serif',
          'font-weight': 'bold',
          'font-size': '12px',
          'fill': '#888'
        } );

    stats_vmpooler_weekly__svg[ 'boot_avg__day' ]
      .append( 'path' )
        .attr( {
          'class': 'area',
          'fill': 'crimson',
          'opacity': '0.75',
          'd': area_boot_avg( stats_vmpooler_weekly__data[ 'boot_avg' ] )
        } );

    stats_vmpooler_weekly__svg[ 'boot_avg__day' ]
      .append( 'path' )
        .attr( {
          'class': 'area',
          'fill': 'url( #background )',
          'opacity': '0.50',
          'd': area_boot_avg( stats_vmpooler_weekly__data[ 'boot_avg' ] )
        } );

    stats_vmpooler_weekly__svg[ 'boot_avg__day' ]
      .append( 'text' )
        .text(
          ( 'boot time ( average )' )
        )
        .attr( {
          'x': '5',
          'y': clone_weekly_height + 20,
          'font-face': '\'PT Sans\', sans-serif',
          'font-weight': 'bold',
          'font-size': '12px',
          'fill': '#888'
        } );
//

  }
);

