class Dashing.Nagios extends Dashing.Widget

  ready: ->
    tierElement = $(@node).find("p[class='tier']")
    tier = tierElement.text()
    tierElement.addClass tier.toLowerCase()

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
