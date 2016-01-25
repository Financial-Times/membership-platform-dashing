require 'net/http'
require 'json'

def performCheckAndSendEventToWidgets(widgetId, urlHostName, urlPath, tlsEnabled)

  if tlsEnabled
    http = Net::HTTP.new(urlHostName, 443)
    http.use_ssl = true
  else
    http = Net::HTTP.new(urlHostName, 80)
  end

  response = http.request(Net::HTTP::Get.new(urlPath))

  if response.code == '200'
    print 'bla'
    send_event(widgetId, { value: 'ok', status: 'available' })
  else
    print 'bla bla'
    send_event(widgetId, { value: 'danger', status: 'unavailable' })
  end

end

performCheckAndSendEventToWidgets('login', 'login-api-at-eu-prod.herokuapp.com', '/admin/healthcheck', true)