require 'net/http'
require 'json'
require 'rest-client'
require 'cgi'
require 'json'

apiKey = ENV['PINGDOM_API_KEY'] || ''
user = ENV['PINGDOM_USER'] || ''
password = ENV['PINGDOM_PASSWORD'] || ''

def performCheckAndSendEventToWidgets(widgetId, urlHostName, urlPath, tlsEnabled)

  if tlsEnabled
    http = Net::HTTP.new(urlHostName, 443)
    http.use_ssl = true
  else
    http = Net::HTTP.new(urlHostName, 80)
  end

  response = http.request(Net::HTTP::Get.new(urlPath))

  if response.code == '200'
    send_event(widgetId, { value: 'ok', status: 'available' })
  else
    send_event(widgetId, { value: 'danger', status: 'unavailable' })
  end

end

def getUptimeMetricsFromPingdom(checkId, apiKey, user, password)

  # Get the unix timestamps
  timeInSecond = 7 * 24 * 60 * 60
  lastTime = (Time.now.to_i - timeInSecond )

  urlUptime = "https://#{CGI::escape user}:#{CGI::escape password}@api.pingdom.com/api/2.0/summary.average/#{checkId}?from=#{lastTime}&includeuptime=true"
  responseUptime = RestClient.get(urlUptime, {"App-Key" => apiKey, "Account-Email" => "ftpingdom@ft.com"})
  responseUptime = JSON.parse(responseUptime.body, :symbolize_names => true)

  totalUp = responseUptime[:summary][:status][:totalup]
  totalDown = responseUptime[:summary][:status][:totaldown]
  uptime = (100 * (totalUp.to_f / (totalDown.to_f + totalUp.to_f))).round(2)

  if uptime >= 99.90
    send_event(checkId, { current: uptime, status: 'uptime-999-or-above' })
  else
    send_event(checkId, { current: uptime, status: 'uptime-below-999' })
  end



end

SCHEDULER.every '10s', first_in: 0 do |job|

  performCheckAndSendEventToWidgets('login', 'login-api-at-eu-prod.herokuapp.com', '/tests/critical', true)
  performCheckAndSendEventToWidgets('change-credentials', 'ft-memb-user-cred-svc-at-elb-eu-946129326.eu-west-1.elb.amazonaws.com', '/tests/change-credentials-critical', false)
  performCheckAndSendEventToWidgets('reset-password', 'ft-memb-user-cred-svc-at-elb-eu-946129326.eu-west-1.elb.amazonaws.com', '/tests/reset-password-critical', false)
  performCheckAndSendEventToWidgets('validate-session', 'ft-memb-session-api-at-elb-p-301208839.eu-west-1.elb.amazonaws.com', '/tests/critical-validate', false)
  performCheckAndSendEventToWidgets('revoke-session', 'ft-memb-session-api-at-elb-p-301208839.eu-west-1.elb.amazonaws.com', '/tests/critical-revoke', false)
  getUptimeMetricsFromPingdom('1965634', apiKey, user, password)
  getUptimeMetricsFromPingdom('1974827', apiKey, user, password)
  getUptimeMetricsFromPingdom('1974865', apiKey, user, password)
  getUptimeMetricsFromPingdom('2142836', apiKey, user, password)
  getUptimeMetricsFromPingdom('2142839', apiKey, user, password)

end

