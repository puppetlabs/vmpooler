var numbers_url = '/dashboard/stats/vcloud/numbers';
var numbers_width = 130;
var numbers_height = 45;

var stats_vcloud_numbers__data  = {};
var stats_vcloud_numbers__svg   = {};

d3.json( numbers_url,

  function( stats_vcloud_numbers__data ) {

    ( function tick() {
      setTimeout( function() {
        var stats_vcloud_numbers__data__live = ( function() {
          var stats_vcloud_numbers__data__live = null;

          $.ajax( {
            'url': numbers_url,
            'async': false,
            'global': false,
            'dataType': 'json',
            'success': function( data ) {
              stats_vcloud_numbers__data__live = data;
            }
          } );

          return stats_vcloud_numbers__data__live;
        } )();

        $( '#stats-vcloud-numbers' ).empty();

        stats_vcloud_numbers__svg[ 'ready' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10 25 0 0' )
            .style( 'padding', '0 0 20 0' )
            .attr( 'width', numbers_width )
            .attr( 'height', numbers_height );

        stats_vcloud_numbers__svg[ 'ready' ]
          .append( 'text' )
            .text(
              ( 'ready and waiting' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height + 6,
              'font-face': 'PT Sans sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vcloud_numbers__svg[ 'ready' ]
          .append( 'text' )
            .text(
              ( stats_vcloud_numbers__data__live[ 'ready' ] )
            )
            .attr( {
              'x': '0',
              'y': '36',
              'font-face': 'PT Sans sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vcloud_numbers__svg[ 'pending' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10 25 0 0' )
            .style( 'padding', '0 0 20 0' )
            .attr( 'width', numbers_width )
            .attr( 'height', numbers_height );

        stats_vcloud_numbers__svg[ 'pending' ]
          .append( 'text' )
            .text(
              ( 'being built' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height + 6,
              'font-face': 'PT Sans sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vcloud_numbers__svg[ 'pending' ]
          .append( 'text' )
            .text(
              ( stats_vcloud_numbers__data__live[ 'pending' ] )
            )
            .attr( {
              'x': '0',
              'y': '36',
              'font-face': 'PT Sans sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vcloud_numbers__svg[ 'running' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10 25 0 0' )
            .style( 'padding', '0 0 20 0' )
            .attr( 'width', numbers_width )
            .attr( 'height', numbers_height );

        stats_vcloud_numbers__svg[ 'running' ]
          .append( 'text' )
            .text(
              ( 'running tests' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height + 6,
              'font-face': 'PT Sans sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vcloud_numbers__svg[ 'running' ]
          .append( 'text' )
            .text(
              ( stats_vcloud_numbers__data__live[ 'running' ] )
            )
            .attr( {
              'x': '0',
              'y': '36',
              'font-face': 'PT Sans sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vcloud_numbers__svg[ 'completed' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10 25 0 0' )
            .style( 'padding', '0 0 20 0' )
            .attr( 'width', numbers_width )
            .attr( 'height', numbers_height );

        stats_vcloud_numbers__svg[ 'completed' ]
          .append( 'text' )
            .text(
              ( 'waiting to die' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height + 6,
              'font-face': 'PT Sans sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vcloud_numbers__svg[ 'completed' ]
          .append( 'text' )
            .text(
              ( stats_vcloud_numbers__data__live[ 'completed' ] )
            )
            .attr( {
              'x': '0',
              'y': '36',
              'font-face': 'PT Sans sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        tick();
      }, 5000 );
    } )();

  }

);

