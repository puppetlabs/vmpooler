var pool_url = '/dashboard/stats/vcloud/pool';
var pool_width = 130;
var pool_height = 85;

var stats_vcloud_pool__data  = {};
var stats_vcloud_pool__svg   = {};

d3.json( pool_url+'?history=1',

  function( stats_vcloud_pool__data ) {

    var stats_vcloud_pool__data__keys = [];

    for ( var key in stats_vcloud_pool__data ) {
      stats_vcloud_pool__data__keys.push( key );
    }

    stats_vcloud_pool__data__keys.sort().map(
      function( pool ) {
        stats_vcloud_pool__data[ pool ][ 'r' ] = stats_vcloud_pool__data[ pool ][ 'history' ];
      }
    );

    ( function tick() {
      setTimeout( function() {
        var stats_vcloud_pool__data__live = ( function() {
          var stats_vcloud_pool__data__live = null;

          $.ajax( {
            'url': pool_url,
            'async': false,
            'global': false,
            'dataType': 'json',
            'success': function( data ) {
              stats_vcloud_pool__data__live = data;
            }
          } );
          
          return stats_vcloud_pool__data__live;
        } )();

        $( '#stats-vcloud-pool' ).empty();

        stats_vcloud_pool__data__keys.sort().map(
          function( pool ) {
            var x = d3.scale.linear().domain( [ 0, 500 ] ).range( [ 0, pool_width ] );
            var y = d3.scale.linear().domain( [ parseInt( stats_vcloud_pool__data__live[ pool ][ 'size' ] ), 0 ] ).range( [ 0, pool_height ] );

            var area = d3.svg.area()
              .interpolate( 'basis' )
              .x( function( d, i ) { return x( i ); } )
              .y0( pool_height - 15 )
              .y1( function( d ) { return y( d ); } );
    
            var path = d3.svg.line()
              .interpolate( 'basis' )
              .x( function( d, i ) { return x( i ); } )
              .y( function( d ) { return y( d ); } );

            stats_vcloud_pool__data[ pool ][ 'r' ].push( parseInt( stats_vcloud_pool__data__live[ pool ][ 'ready' ] ) );

            var pool_current = stats_vcloud_pool__data[ pool ][ 'r' ].slice( -1 )[ 0 ];
            var pool_size    = stats_vcloud_pool__data[ pool ][ 'size' ]
            var pool_pct     = Math.floor( ( pool_current / pool_size ) * 100 );

            var statuscolor = '#78a830';
            if ( pool_pct < 50 ) { statuscolor = '#f0a800'; }
            if ( pool_pct < 25 ) { statuscolor = '#d84830'; }

            stats_vcloud_pool__svg[ pool ] = d3.select( '#stats-vcloud-pool' )
              .append( 'svg' )
                .style( 'margin', '15px 25px 0px 0px' )
                .style( 'padding', '0px 0px 20px 0px' )
                .attr( 'width', pool_width )
                .attr( 'height', pool_height );

            stats_vcloud_pool__svg[ pool ]
              .append( 'g' )
              .attr( 'class', 'x tick' )
              .attr( 'transform', 'translate( 0,' + ( pool_height - 15 ) + ')' )
              .call(
                d3.svg.axis()
                  .scale( x )
                  .ticks( 4 )
                  .tickSize( -pool_height )
                  .outerTickSize( 0 )
                  .tickFormat( '' )
                  .tickSubdivide( true )
                  .orient( 'bottom' )
              );

            stats_vcloud_pool__svg[ pool ]
              .append( 'text' )
                .text(
                  ( pool )
                )
                .attr( {
                  'x': '5',
                  'y': pool_height - 2,
                  'font-face': '\'PT Sans\', sans-serif',
                  'font-weight': 'bold',
                  'font-size': '12px',
                  'fill': '#888'
                } );

            stats_vcloud_pool__svg[ pool ]
              .append( 'text' )
                .text(
                  ( pool_pct + '%' )
                )
                .attr( {
                  'x': '5',
                  'y': pool_height - 20,
                  'font-face': '\'PT Sans\', sans-serif',
                  'font-weight': 'bold',
                  'font-size': '12px',
                  'letter-spacing': '-0.05em',
                  'fill': '#888'
                } );

            stats_vcloud_pool__svg[ pool ]
              .append( 'text' )
                .text(
                  ( '( ' ) +
                  ( pool_current ) +
                  ( '/' ) +
                  ( pool_size ) +
                  ( ' )' )
                )
                .attr( {
                  'x': 40,
                  'y': pool_height - 20,
                  'font-face': '\'PT Sans\', sans-serif',
                  'font-size': '12px',
                  'letter-spacing': '-0.05em',
                  'fill': '#888'
                } );

            stats_vcloud_pool__svg[ pool ]
              .append( 'path' )
                .attr( 'class', 'area' )
                .attr( 'fill', statuscolor )
                .attr( 'opacity', '0.25' )
                .attr( 'd', area( stats_vcloud_pool__data[ pool ][ 'r' ] ) );

            stats_vcloud_pool__svg[ pool ]
              .append( 'path' )
                .attr( 'class', 'line' )
                .attr( 'stroke', statuscolor )
                .attr( 'stroke-width', '1' )
                .attr( 'd', path( stats_vcloud_pool__data[ pool ][ 'r' ] ) );

            if ( stats_vcloud_pool__data[ pool ][ 'r' ].length > 500 ) {
              stats_vcloud_pool__data[ pool ][ 'r' ].shift();
            }
          }
        )

        tick();
      }, 5000 );
    } )();

  }

);

