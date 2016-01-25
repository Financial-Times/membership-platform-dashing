class Dashing.Availability extends Dashing.Widget

  onData: (data) ->
    # clear existing "status-*" classes
    $(@get('node')).attr 'class', (i,c) -> c.replace /\bstatus-\S+/g, ''

    # add new class
    $(@get('node')).addClass "status-#{data.value}"
    $(@get('node')).addClass "status-#{data.status}"