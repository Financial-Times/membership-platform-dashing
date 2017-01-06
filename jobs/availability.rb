require 'net/http'
require 'json'
require 'rest-client'
require 'cgi'
require 'json'

apiKey = ENV['PINGDOM_API_KEY'] || ''
logentriesApiKey = ENV['LOGENTRIES_API_KEY'] || ''
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
  lastTime = (Time.now.to_i - timeInSecond)

  urlUptime = "https://#{CGI::escape user}:#{CGI::escape password}@api.pingdom.com/api/2.0/summary.average/#{checkId}?from=#{lastTime}&includeuptime=true"
  responseUptime = RestClient.get(urlUptime, {"App-Key" => apiKey, "Account-Email" => "ftpingdom@ft.com"})
  responseUptime = JSON.parse(responseUptime.body, :symbolize_names => true)

  avgResponseTime = responseUptime[:summary][:responsetime][:avgresponse]
  send_event(checkId+"resp", { current: avgResponseTime, status: 'uptime-999-or-above'})

  totalUp = responseUptime[:summary][:status][:totalup]
  totalDown = responseUptime[:summary][:status][:totaldown]
  uptime = (100 * (totalUp.to_f / (totalDown.to_f + totalUp.to_f))).round(2)

  if uptime >= 99.90
    send_event(checkId, { current: uptime, status: 'uptime-999-or-above' })
  else
    send_event(checkId, { current: uptime, status: 'uptime-below-999' })
  end

end

def getResponseTimeMetricsFromLogentries(dataId, query, apiKey, logkey, criticalThreshold)

  # Get the unix timestamps
  _24hoursInSeconds = 12 * 60 * 60
  timeNow = Time.now.to_i


  from = (timeNow - _24hoursInSeconds) * 1000
  to = timeNow * 1000

  urlUptime = "https://rest.logentries.com/query/logs/#{logkey}?to=#{to}&from=#{from}&query=#{query}"
  response = RestClient.get(urlUptime, {"X-Api-Key" => apiKey})

  stats = nil

  while stats.nil?
    jsonResponse = JSON.parse(response.body, :symbolize_names => true)
    stats = jsonResponse[:statistics]
    if stats.nil?
      linkToFollow = jsonResponse[:links][0][:href]
      response = RestClient.get(linkToFollow, {"X-Api-Key" => apiKey})
      print response
      print "\n"
      sleep 5
    end
  end

  perc95Series = jsonResponse[:statistics][:timeseries][:rt]
  status = 'green'
  points = []
  (0..11).each do |i|
    if perc95Series[i][:percentile] > criticalThreshold
      status = 'orange'
    end
    points << { x: i, y: perc95Series[i][:percentile] }
  end

  print "\n #{points}"

  send_event(dataId, points: points, status: status)

end

SCHEDULER.every '30s', first_in: 0 do |job|

  performCheckAndSendEventToWidgets('login', 'login-api-at-eu-prod.herokuapp.com', '/tests/critical', true)
  performCheckAndSendEventToWidgets('change-credentials', 'ft-memb-user-cred-svc-at-elb-eu-946129326.eu-west-1.elb.amazonaws.com', '/tests/change-credentials-critical', false)
  performCheckAndSendEventToWidgets('reset-password', 'ft-memb-user-cred-svc-at-elb-eu-946129326.eu-west-1.elb.amazonaws.com', '/tests/reset-password-critical', false)
  performCheckAndSendEventToWidgets('validate-session', 'ft-memb-session-api-at-elb-p-301208839.eu-west-1.elb.amazonaws.com', '/tests/critical-validate', false)
  performCheckAndSendEventToWidgets('get-user-products', 'usr-product-svc-at-eu-prod.herokuapp.com', '/tests/get-products-critical', false)
  performCheckAndSendEventToWidgets('authorise-content', 'ft-memb-access-service-at-elb-eu-287296531.eu-west-1.elb.amazonaws.com', '/tests/authorise-content-critical', false)
  performCheckAndSendEventToWidgets('retrieve-user-profile', 'user-profile-svc-at-lb-eu-west-1.memb.ft.com', '/tests/get-profile-critical', true)
  performCheckAndSendEventToWidgets('customer-sso', 'customer-sso-at-eu-prod.herokuapp.com', '/tests', true)
  getUptimeMetricsFromPingdom('1965634', apiKey, user, password)
  getUptimeMetricsFromPingdom('1974827', apiKey, user, password)
  getUptimeMetricsFromPingdom('1974865', apiKey, user, password)
  getUptimeMetricsFromPingdom('2142836', apiKey, user, password)
  getUptimeMetricsFromPingdom('2147820', apiKey, user, password)
  getUptimeMetricsFromPingdom('2225403', apiKey, user, password)
  getUptimeMetricsFromPingdom('2005882', apiKey, user, password)
  getUptimeMetricsFromPingdom('2433995', apiKey, user, password)

end

#SCHEDULER.every '600s', first_in: 0 do |job|

  #getResponseTimeMetricsFromLogentries('validate-session-rt-metrics', 'where(%2F%5C%2Fsessions.*%20(%3FP%3Crt%3E%5Cd%2B)%24%2F)%20calculate(percentile(95)%3Art)%20timeslice(12)', logentriesApiKey, '574a6e5c-cc27-4362-bed6-e93df3730a72', 300)
  #getResponseTimeMetricsFromLogentries('get-user-products-rt-metrics', 'where(%2F%5C%2Fusers%5C%2F.*%5C%2Fproducts.*%20(%3FP%3Crt%3E%5Cd%2B)%24%2F)calculate(percentile(95)%3Art)%20timeslice(12)', logentriesApiKey, '574a6e5c-cc27-4362-bed6-e93df3730a72', 300)
  #getResponseTimeMetricsFromLogentries('login-rt-metrics', 'where(%2FPOST%20%5C%2Flogin%20.*%20(%3FP%3Crt%3E%5Cd%2B)%24%2F)%20calculate(percentile(95)%3Art)%20timeslice(12)', logentriesApiKey, '2ef22249-9bf5-49c7-8024-79e3d5462de8', 300)
  #getResponseTimeMetricsFromLogentries('login-rt-metrics', 'where(%2F%5C%2Fusers%5C%2F.*%5C%2Fprofile.*%20(%3FP%3Crt%3E%5Cd%20)%24%2F)calculate(percentile(95)%3Art)%20timeslice(12)', logentriesApiKey, '574a6e5c-cc27-4362-bed6-e93df3730a72', 300)

#end

