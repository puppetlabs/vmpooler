var numbers_url = '/status';
var numbers_width = 110;
var numbers_height = 50;

var stats_vmpooler_numbers__data  = {};
var stats_vmpooler_numbers__svg   = {};

d3.json( numbers_url,

  function( stats_vmpooler_numbers__data ) {

    ( function tick() {
      setTimeout( function() {
        var stats_vmpooler_numbers__data__live = ( function() {
          var stats_vmpooler_numbers__data__live = null;

          $.ajax( {
            'url': numbers_url,
            'async': false,
            'global': false,
            'dataType': 'json',
            'success': function( data ) {
              stats_vmpooler_numbers__data__live = data;
            }
          } );

          return stats_vmpooler_numbers__data__live;
        } )();

        $( '#stats-vmpooler-numbers' ).empty();

        stats_vmpooler_numbers__svg[ 'clone_total' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'class', 'extra' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'clone_total' ]
          .append( 'text' )
            .text(
              ( 'cloned today' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'clone_total' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'clone' ][ 'count' ][ 'total' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vmpooler_numbers__svg[ 'clone_average' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'class', 'extra' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'clone_average' ]
          .append( 'text' )
            .text(
              ( 'clone time average' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'clone_average' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'clone' ][ 'duration' ][ 'average' ] + 's' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vmpooler_numbers__svg[ 'capacity' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'class', 'extra' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'capacity' ]
          .append( 'text' )
            .text(
              ( 'capacity percent' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'capacity' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'capacity' ][ 'percent' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vmpooler_numbers__svg[ 'total' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'total' ]
          .append( 'text' )
            .text(
              ( 'total # of VMs' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'total' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'queue' ][ 'total' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vmpooler_numbers__svg[ 'ready' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'ready' ]
          .append( 'text' )
            .text(
              ( 'ready and waiting' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'ready' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'queue' ][ 'ready' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vmpooler_numbers__svg[ 'cloning' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'cloning' ]
          .append( 'text' )
            .text(
              ( 'being cloned' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'cloning' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'queue' ][ 'cloning' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vmpooler_numbers__svg[ 'booting' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'booting' ]
          .append( 'text' )
            .text(
              ( 'booting up' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'booting' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'queue' ][ 'booting' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );







        stats_vmpooler_numbers__svg[ 'running' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'running' ]
          .append( 'text' )
            .text(
              ( 'running tests' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'running' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'queue' ][ 'running' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': '36',
              'font-face': '\'PT Sans\', sans-serif',
              'font-weight': 'bold',
              'font-size': '50px',
              'letter-spacing': '-0.05em',
              'fill': '#444'
            } );

        stats_vmpooler_numbers__svg[ 'completed' ] = d3.select( '#stats-vmpooler-numbers' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .style( 'text-align', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'completed' ]
          .append( 'text' )
            .text(
              ( 'waiting to die' )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
              'y': numbers_height,
              'font-face': '\'PT Sans\', sans-serif',
              'font-size': '12px',
              'font-weight': 'bold',
              'fill': '#888'
            } );

        stats_vmpooler_numbers__svg[ 'completed' ]
          .append( 'text' )
            .text(
              ( stats_vmpooler_numbers__data__live[ 'queue' ][ 'completed' ] )
            )
            .attr( {
              'text-anchor': 'end',
              'x': numbers_width,
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

