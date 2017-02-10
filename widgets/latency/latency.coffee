class Dashing.Graphite extends Dashing.Widget

  ready: ->
    tierElement = $(@node).find("p[class='tier']")
    tier = tierElement.text()
    tierElement.addClass tier.toLowerCase()

  onData: (data) ->
    
