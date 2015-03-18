function whichDay( dateString ) {
  var daysOfWeek = new Array( 'mon.', 'tues.', 'wed.', 'thur.', 'fri.', 'sat.', 'sun.' );
  return daysOfWeek[ new Date( dateString ).getDay() ];
}

Date.prototype.yyyymmdd = function() {
  var yyyy = this.getFullYear().toString();
  var mm = (this.getMonth()+1).toString();
  var dd = this.getDate().toString();
  return yyyy + '-' + ( mm[1] ? mm : '0' + mm[0] ) + '-' + ( dd[1] ? dd : '0' + dd[0] );
};

var date_from = new Date();
date_from.setDate( date_from.getDate() - 6 );

var numbers_url = '/summary?from=' + date_from.yyyymmdd();
var numbers_width = 150;
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

        $( '#stats-vmpooler-numbers-weekly' ).empty();

        stats_vmpooler_numbers__svg[ 'boot_average' ] = d3.select( '#stats-vmpooler-numbers-weekly' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'boot_average' ]
          .append( 'text' )
            .text(
              ( 'boot time average' )
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

        stats_vmpooler_numbers__svg[ 'boot_average' ]
          .append( 'text' )
            .text(
              ( ( Math.round( stats_vmpooler_numbers__data__live[ 'boot' ][ 'duration' ][ 'average' ] * 10 ) / 10 ) + 's' )
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

        stats_vmpooler_numbers__svg[ 'clone_average' ] = d3.select( '#stats-vmpooler-numbers-weekly' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
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
              ( ( Math.round( stats_vmpooler_numbers__data__live[ 'clone' ][ 'duration' ][ 'average' ] * 10 ) / 10 ) + 's' )
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

        stats_vmpooler_numbers__data[ 'clone_best_day' ] = '';
        stats_vmpooler_numbers__data[ 'clone_total' ] = [];

        stats_vmpooler_numbers__data__live[ 'daily' ].sort().map(
          function( day ) {
            stats_vmpooler_numbers__data[ 'clone_total' ].push( parseInt( day[ 'clone' ][ 'count' ][ 'total' ] ) );
          }
        );

        stats_vmpooler_numbers__data__live[ 'daily' ].sort().map(
          function( day ) {
            if ( day[ 'clone' ][ 'count' ][ 'total' ] == Math.max.apply( Math, stats_vmpooler_numbers__data[ 'clone_total' ] ) ) {
              stats_vmpooler_numbers__data[ 'clone_best_day' ] = day[ 'date' ];
            }
          }
        );

        stats_vmpooler_numbers__svg[ 'best_day' ] = d3.select( '#stats-vmpooler-numbers-weekly' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'best_day' ]
          .append( 'text' )
            .text(
              ( 'most clones' )
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

        stats_vmpooler_numbers__svg[ 'best_day' ]
          .append( 'text' )
            .text(
              ( whichDay( stats_vmpooler_numbers__data[ 'clone_best_day' ] ) )
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


        stats_vmpooler_numbers__svg[ 'clone_total' ] = d3.select( '#stats-vmpooler-numbers-weekly' )
          .append( 'svg' )
            .style( 'margin', '15px 0px 0px 0px' )
            .style( 'padding', '0px 10px 20px 10px' )
            .style( 'float', 'right' )
            .attr( 'width', numbers_width + 'px' )
            .attr( 'height', numbers_height + 'px' );

        stats_vmpooler_numbers__svg[ 'clone_total' ]
          .append( 'text' )
            .text(
              ( 'cloned this week' )
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
              ( stats_vmpooler_numbers__data__live[ 'clone' ][ 'count' ][ 'total' ].toLocaleString() )
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

