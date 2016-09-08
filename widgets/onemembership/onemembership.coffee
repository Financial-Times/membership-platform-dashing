class Dashing.Onemembership extends Dashing.Widget

  ready: ->


  onData: (data) ->
    # clear existing "status-*" classes
    $(@get('node')).attr 'class', (i,c) -> c.replace /\bstatus-\S+/g, ''
    # add new class
    $(@get('node')).addClass "status-#{data.value}"
    $(@get('node')).addClass "status-#{data.status}"

    # remove existing alerts if status OK
    if(data.value == 'ok')
      removeAlert(data.identifier)
    else # If monitor failed
      # Get parent list item
      parentListItem = $(@get('node')).parent()

      # Get grandparent ul
      grandparent = $(@get('node')).parent().parent()
      fixLayout(parentListItem, grandparent)

    if($(@node).hasClass("status-danger"))
      # Add to failure overlay
      dataId = $(@node).attr('data-id')
      # Check first if monitor was already added
      failureOverlayContent = $('#overlay-content', window.parent.document)
      if(failureOverlayContent.find("div[data-id=" + dataId + "]").length == 0)
        failureOverlayContent.append($(@node).parent().clone())
        fixLayout(failureOverlayContent.find("div[data-id=" + dataId + "]").parent(), failureOverlayContent)

  removeAlert = (identifier) ->
    spanAlert = $('#alerts', window.parent.document).find("span[alert-id=#{identifier}]")
    # Only remove if it exists
    if(spanAlert.length)
      spanAlert.remove()

  maxColumn = 5

  fixLayout = (failingNode, baseElement) ->
    # Move to first column and row
    failingNode.attr("data-col", 1)
    failingNode.attr("data-row", 1)

    failures = getParentListItems(baseElement, 'div.status-danger')
    passing = getParentListItems(baseElement, 'div.status-ok')
    nextCell =
      col: 1
      rw: 1
    if(failures.length)
      nextCell = reorder(failures, 1, 1) # Reorder failures

    reorder(passing, nextCell.col, nextCell.rw) # Reorder passing

  getParentListItems = (baseElement, selector) ->
    parentListItems = new Array()
    results = baseElement.find(selector)
    results.each ->
      parentListItem = $(@).parent()
      parentListItems.push(parentListItem)
    parentListItems

  reorder = (items, column, row) ->
    for item in items
      if(column > maxColumn)
        column = 1
        row = row + 1
      item.attr("data-col", column)
      item.attr("data-row", row)
      column += 1
    nextCell =
      col: column
      rw: row
