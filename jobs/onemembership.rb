require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'json'
require 'rest-client'
require 'cgi'
require 'json'

apiKey = ENV['PINGDOM_API_KEY'] || ''
logentriesApiKey = ENV['LOGENTRIES_API_KEY'] || ''
user = ENV['PINGDOM_USER'] || ''
password = ENV['PINGDOM_PASSWORD'] || ''
s3oCredentials = ENV['S3O_COOKIE'] || ''

def performCheckAndSendEventToWidgets(widgetId, urlHostName, urlPath, tlsEnabled)

  if tlsEnabled
    http = Net::HTTP.new(urlHostName, 443)
    http.use_ssl = true
  else
    http = Net::HTTP.new(urlHostName, 80)
  end

  response = http.request(Net::HTTP::Get.new(urlPath))
  if response.code == '200'
    send_event(widgetId, { identifier: widgetId, value: 'ok', status: 'available' })
  else
    failures = getTestFailures(response)
    send_event('alerts', { identifier: widgetId, value: failures.to_s })
    send_event(widgetId, { identifier: widgetId, value: 'danger', status: 'unavailable' })
  end
  sleep(1)
end

def getStatusFromHealthCheck(widgetId, urlHost, urlPath, s3oCredentials)
  healthCheckUrl = urlHost + urlPath
  cookieValue = 's3o-credentials=' + s3oCredentials
  page = Nokogiri::HTML(open(healthCheckUrl, 'Cookie' => cookieValue))
  status = page.at_css('#status > div').inner_text
  if status == 'OK'
    send_event(widgetId, { identifier: widgetId, value: 'ok', status: 'available' })
  else
    failures = getHealthcheckFailures(page)
    send_event('alerts', { identifier: widgetId, value: failures.to_s })
    send_event(widgetId, { identifier: widgetId, value: 'danger', status: 'unavailable' })
  end
  sleep(1)
end

def getStatusFromNagios(widgetId, urlHost, urlPath)
  nagiosUrl = urlHost + urlPath
  page = Nokogiri::HTML(open(nagiosUrl))
  warn = '0'
  crit = '0'
  warnEl = page.at_css('td.serviceTotalsWARNING')
  critEl = page.at_css('td.serviceTotalsCRITICAL')
  unless warnEl.nil? || warnEl == 0
    warn = page.at_css('td.serviceTotalsWARNING').inner_text
  end
  unless critEl.nil? || critEl == 0
    crit = page.at_css('td.serviceTotalsCRITICAL').inner_text
  end
  if crit == '0'
    send_event(widgetId, { identifier: widgetId, critical: crit, warning: warn, value: 'ok', status: 'available'})
  else
    send_event(widgetId, { identifier: widgetId, critical: crit, warning: warn, value: 'danger', status: 'unavailable'})
  end
  sleep(1)
end

def failHealthCheck(widgetId, urlHost, urlPath, s3oCredentials)
  send_event('alerts', { identifier: widgetId, value: 'Dependency session-api not healthy' })
  send_event(widgetId, { identifier: widgetId, value: 'danger', status: 'unavailable' })
  sleep(1)
end

def getHealthcheckFailures(page)
  failingListItems = page.css('#checklist > li.error')
  failures = Array.new
  for failingListItem in failingListItems
    failures.push(failingListItem.inner_text)
  end
  failures
end

def getTestFailures(response)
  jsonResponse = JSON.parse(response.body)
  tests = jsonResponse['tests']
  failures = Array.new
  tests.each do |test|
    passed = test['passed']
    unless passed
      failures.push(test['testName'].to_s)
    end
  end
  failures
end

SCHEDULER.every '30s', first_in: 0 do |job|

  performCheckAndSendEventToWidgets('login-tests-eu', 'login-api-at-eu-prod.herokuapp.com', '/tests/critical', true)
  performCheckAndSendEventToWidgets('login-tests-us', 'login-api-at-us-prod.herokuapp.com', '/tests/critical', true)
  performCheckAndSendEventToWidgets('user-cred-tests-eu', 'ft-memb-user-cred-svc-at-elb-eu-946129326.eu-west-1.elb.amazonaws.com', '/tests/change-credentials-critical', false)
  performCheckAndSendEventToWidgets('access-service-tests-eu', 'ft-memb-access-service-at-elb-eu-287296531.eu-west-1.elb.amazonaws.com', '/tests/authorise-content-critical', false)
  performCheckAndSendEventToWidgets('user-products', 'usr-product-svc-at-eu-prod.herokuapp.com', '/tests/get-products-critical', true)
  performCheckAndSendEventToWidgets('login-app-tests-eu', 'login-app-at-eu-prod.herokuapp.com', '/tests', true)
  performCheckAndSendEventToWidgets('login-app-tests-us', 'login-app-at-us-prod.herokuapp.com', '/tests', true)
  getStatusFromHealthCheck('loginapi-eu', 'http://healthcheck.ft.com', '/service/399714ea73e0015e425666917931e6a4', s3oCredentials)
  getStatusFromHealthCheck('loginapi-us', 'http://healthcheck.ft.com', '/service/ad9e37cf76f09190d5e39a9fd71a874f', s3oCredentials)
  getStatusFromHealthCheck('loginapp-eu', 'http://healthcheck.ft.com', '/service/28c1512a87c1bb807ed55a6ecd7798b1', s3oCredentials)
  getStatusFromHealthCheck('loginapp-us', 'http://healthcheck.ft.com', '/service/ce39ec61ec18eefb5fadb9d4a89d1543', s3oCredentials)
  getStatusFromHealthCheck('usr-product-svc-eu', 'http://healthcheck.ft.com', '/service/993cc7443e3161a3c4d5e0081b13e44d', s3oCredentials)
  getStatusFromHealthCheck('usr-product-svc-us', 'http://healthcheck.ft.com', '/service/2e770914bca342d7bf9d8589efb29539', s3oCredentials)
  getStatusFromHealthCheck('session-user-data', 'http://healthcheck.ft.com', '/service/a6d88564f925fd8f16e6eae588b2f145', s3oCredentials)
end

SCHEDULER.every '30s', first_in: 0 do |job|

  performCheckAndSendEventToWidgets('user-profile', 'user-profile-svc-at-lb-eu-west-1.memb.ft.com', '/tests/get-profile-critical', true)
  getStatusFromHealthCheck('user-profile-eu', 'http://healthcheck.ft.com', '/service/7b02faa0e45544c26c7f4dddcdafa251', s3oCredentials)
  getStatusFromHealthCheck('user-profile-us', 'http://healthcheck.ft.com', '/service/41ddaf5f7110db4f05cf1104d21c0d78', s3oCredentials)

end

SCHEDULER.every '15s', first_in: 0 do |job|
  getStatusFromNagios('session-service-us-nagios', 'http://ftmon04010-lvnj-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi?host=all&sorttype=2&sortoption=3')
  getStatusFromNagios('apps-memb-us-nagios', 'http://ftmon32370-lae1a-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon65966-law1c-eu-p', 'http://ftmon65966-law1c-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon65973-lae1c-us-p', 'http://ftmon65973-lae1c-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon04002-lviw-uk-p', 'http://ftmon04002-lviw-uk-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon04010-lvnj-us-p', 'http://ftmon04010-lvnj-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon04002-lviw-uk-p-nagios', 'http://ftmon04002-lviw-uk-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon04010-lvnj-us-p-nagios', 'http://ftmon04010-lvnj-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon65966-law1c-eu-p-nagios', 'http://ftmon65966-law1c-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon65973-lae1c-us-p-nagios', 'http://ftmon65973-lae1c-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon40525-law1a-eu-p-nagios', 'http://ftmon40525-law1a-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon40529-lae1a-us-p-nagios', 'http://ftmon40529-lae1a-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
end

SCHEDULER.every '35s', first_in: 0 do |job|
end

