$(function() {
  var relatizer = function(){
    var dt = $(this).text(), relatized = $.relatizeDate(this)
    if ($(this).parents("a").length > 0 || $(this).is("a")) {
      $(this).relatizeDate()
      if (!$(this).attr('title')) {
        $(this).attr('title', dt)
      }
    } else {
      $(this)
      .text('')
      .append( $('<a href="#" class="toggle_format" title="' + dt + '" />')
              .append('<span class="date_time">' + dt +
                      '</span><span class="relatized_time">' +
                        relatized + '</span>') )
    }
  };

  $('.time').each(relatizer);

  $('.time a.toggle_format .date_time').hide();

  var format_toggler = function(){
    $('.time a.toggle_format span').toggle();
    $(this).attr('title', $('span:hidden',this).text());
    return false;
  };

  $('.time a.toggle_format').click(format_toggler);

  $('ul li.job').hover(function() {
    $(this).addClass('hover');
  }, function() {
    $(this).removeClass('hover');
  })

  $('a.backtrace').click(function (e) {
    e.preventDefault();
    if($(this).prev('div.backtrace:visible').length > 0) {
      $(this).next('div.backtrace').show();
      $(this).prev('div.backtrace').hide();
    } else {
      $(this).next('div.backtrace').hide();
      $(this).prev('div.backtrace').show();
    }
  });

  $("#select_all").click(function (e) {
    var checked = $(this).is(':checked');
    $('.bulk_check').attr('checked', checked);
  });

  $("#bulk_action_submit input").click(function() {
    $('#bulk_action_form').attr("action", $(this).attr("action"));
  });

  $(".remove_single").click(function(e) {
    if (!confirm("Are you sure you want to remove the message?")){
      e.preventDefault();
    }
  });

  $(".remove_bulk").click(function(e) {
    if (!confirm("Are you sure you want to remove the selected messages?")){
      e.preventDefault();
    }
  });
})
