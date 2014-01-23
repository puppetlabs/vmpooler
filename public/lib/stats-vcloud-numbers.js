var numbers_url = '/dashboard/stats/vcloud/numbers';
var numbers_width = 130;
var numbers_height = 50;

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

        stats_vcloud_numbers__svg[ 'total' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10px 25px 0px 0px' )
            .style( 'padding', '0px 0px 20px 0px' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vcloud_numbers__svg[ 'total' ]
          .append( 'text' )
            .text(
              ( 'total VMs' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vcloud_numbers__svg[ 'total' ]
          .append( 'text' )
            .text(
              ( stats_vcloud_numbers__data__live[ 'total' ] )
            )
            .attr( {
              'x': '0',
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vcloud_numbers__svg[ 'ready' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10px 25px 0px 0px' )
            .style( 'padding', '0px 0px 20px 0px' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vcloud_numbers__svg[ 'ready' ]
          .append( 'text' )
            .text(
              ( 'ready and waiting' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
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
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vcloud_numbers__svg[ 'cloning' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10px 25px 0px 0px' )
            .style( 'padding', '0px 0px 20px 0px' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vcloud_numbers__svg[ 'cloning' ]
          .append( 'text' )
            .text(
              ( 'being cloned' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vcloud_numbers__svg[ 'cloning' ]
          .append( 'text' )
            .text(
              ( stats_vcloud_numbers__data__live[ 'cloning' ] )
            )
            .attr( {
              'x': '0',
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vcloud_numbers__svg[ 'booting' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10px 25px 0px 0px' )
            .style( 'padding', '0px 0px 20px 0px' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vcloud_numbers__svg[ 'booting' ]
          .append( 'text' )
            .text(
              ( 'booting up' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vcloud_numbers__svg[ 'booting' ]
          .append( 'text' )
            .text(
              ( stats_vcloud_numbers__data__live[ 'booting' ] )
            )
            .attr( {
              'x': '0',
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );







        stats_vcloud_numbers__svg[ 'running' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10px 25px 0px 0px' )
            .style( 'padding', '0px 0px 20px 0px' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vcloud_numbers__svg[ 'running' ]
          .append( 'text' )
            .text(
              ( 'running tests' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
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
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vcloud_numbers__svg[ 'completed' ] = d3.select( '#stats-vcloud-numbers' )
          .append( 'svg' )
            .style( 'margin', '10px 25px 0px 0px' )
            .style( 'padding', '0px 0px 20px 0px' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vcloud_numbers__svg[ 'completed' ]
          .append( 'text' )
            .text(
              ( 'waiting to die' )
            )
            .attr( {
              'x': '5',
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
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
              'font-face': '\'PT Sans\', sans-serif',
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

