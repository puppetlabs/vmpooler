var running_url = '/dashboard/stats/vcloud/running';
var running_height = 120;

var colorscale = d3.scale.category20();
var color = {};

var stats_vcloud_running__data  = {};
var stats_vcloud_running__svg   = {};

var stats_vcloud_running__data__total = 0;

d3.json( running_url+'?history=1',

  function( stats_vcloud_running__data ) {

    if ( typeof stats_vcloud_running__data[ 'stack' ] === 'undefined' ) {
      stats_vcloud_running__data[ 'stack' ] = [];
      stats_vcloud_running__data[ 'stack_t' ] = [];
    }

    for ( var key in stats_vcloud_running__data ) {
      if ( stats_vcloud_running__data[ key ][ 'history' ] ) {
        for ( var c = 0; c < stats_vcloud_running__data[ key ][ 'history' ].length; c++ ) {
          if ( typeof stats_vcloud_running__data[ 'stack' ][ c ] === 'undefined' ) {
            stats_vcloud_running__data[ 'stack' ][ c ] = {};
          }

          stats_vcloud_running__data[ 'stack' ][ c ][ key ] = stats_vcloud_running__data[ key ][ 'history' ][ c ];
        }
      }
    }

    for ( var c in stats_vcloud_running__data[ 'stack' ] ) {
      for ( var n = 0; n < 8; n++ ) {
        stats_vcloud_running__data[ 'stack_t' ].push( stats_vcloud_running__data[ 'stack' ][ c ] );
      }
    }

    stats_vcloud_running__data[ 'stack' ] = stats_vcloud_running__data[ 'stack_t' ];
    delete stats_vcloud_running__data[ 'stack_t' ];

    ( function tick() {
      setTimeout( function() {

        var stats_vcloud_running__data__live = ( function() {
          var stats_vcloud_running__data__live = null;

          $.ajax( {
            'url': running_url,
            'async': false,
            'global': false,
            'dataType': 'json',
            'success': function( data ) {
              stats_vcloud_running__data__live = data;
            }
          } );

          return stats_vcloud_running__data__live;
        } )();

        var stats_vcloud_running__data__keys = [];
        var stats_vcloud_running__data__total__tmp = 0;

        for ( var key in stats_vcloud_running__data__live ) {
          stats_vcloud_running__data__total__tmp = stats_vcloud_running__data__total__tmp + stats_vcloud_running__data__live[ key ][ 'running' ];
          stats_vcloud_running__data__keys.push( key );
          for ( var c = 0; c < Object.keys(stats_vcloud_running__data__keys).length; c++ ) { color[key] = colorscale( c ); }
        }

        if ( stats_vcloud_running__data__total__tmp > stats_vcloud_running__data__total ) {
          stats_vcloud_running__data__total = stats_vcloud_running__data__total__tmp;
        }

        $( '#stats-vcloud-running' ).empty();

        var x = d3.scale.linear().domain( [ 0, 500 ] ).range( [ 0, document.getElementById( 'stats-vcloud-running' ).offsetWidth ] );
        var y = d3.scale.linear().domain( [ 0, stats_vcloud_running__data__total ] ).range( [ running_height, 0 ] );

        var area = d3.svg.area()
          .x( function( d, i ) { return x( i ); } )
          .y0( function( d ) { return y( d.y0 ); } )
          .y1( function( d ) { return y( d.y0 + d.y ); } );

        var path = d3.svg.line()
          .x( function( d, i ) { return x( i ); } )
          .y( function( d ) { return y( d.y0 + d.y ); } );

        var stack = d3.layout.stack()
          .values( function( d ) { return d.values; } );

        if ( typeof stats_vcloud_running__data[ 'stack' ] === 'undefined' ) {
          stats_vcloud_running__data[ 'stack' ] = [];
        }

        stats_vcloud_running__data[ 'tmp' ] = {};

        for ( var key in stats_vcloud_running__data__live ) {
          stats_vcloud_running__data[ 'tmp' ][ key ] = stats_vcloud_running__data__live[ key ][ 'running' ];
        }

        stats_vcloud_running__data[ 'stack' ].push( stats_vcloud_running__data[ 'tmp' ] );

        var stats_vcloud_running__data__graph = stack(
          stats_vcloud_running__data__keys.sort().map(
            function( name ) {
              return {
                name: name,
                values: stats_vcloud_running__data[ 'stack' ].map( function( d ) {
                  return { y: d[ name ] };
               })
              }
            }
          )
        );

        var svg = d3.select( '#stats-vcloud-running' )
          .append( 'svg' )
          .attr( 'height', running_height )
          .style( 'margin-top', '15px' )
          .style( 'margin-bottom', '10px' )
          .append( 'g' );

        var mysvg = svg.selectAll( '#stats-vcloud-running' )
          .data( stats_vcloud_running__data__graph )
          .enter()
          .append( 'g' );

        mysvg.append( 'path' )
          .attr( 'd', function( d ) { return area( d.values ); } )
          .attr( 'clas', 'area' )
          .attr( 'opacity', '0.25' )
          .style( 'fill', function( d ) { return color[ d.name ]; } );

        mysvg.append( 'path' )
          .attr( 'd', function( d ) { return path( d.values ); } )
          .attr( 'class', 'line' )
          .attr( 'stroke', function( d ) { return '#888'; } )
          .attr( 'stroke-width', '1' );

        stats_vcloud_running__data__keys.sort().map(
          function( key ) {
            stats_vcloud_running__svg[ key ] = d3.select( '#stats-vcloud-running' )
              .append( 'svg' )
                .style( 'margin', '0px 0px 0px 0px' )
                .style( 'padding', '0px 10px 10px 10px' )
                .attr( 'width', '130px' )
                .attr( 'height', '12px' );

            stats_vcloud_running__svg[ key ]
              .append( 'rect' )
                .attr( {
                  'x': '5',
                  'y': '3',
                  'width': '10',
                  'height': '10',
                  'opacity': '0.25',
                  'fill': function( d ) { return color[ key ]; }
                } );

            stats_vcloud_running__svg[ key ]
              .append( 'text' )
                .text(
                  ( key )
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
        );

        if ( stats_vcloud_running__data[ 'stack' ].length > 500 ) {
          stats_vcloud_running__data[ 'stack' ].shift();
        }

        tick();
      }, 5000 );
    } )();

  }

);
