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

def getHealth(widgetId, urlHost, urlPath, port, tlsEnabled)
  http = Net::HTTP.new(urlHost, port)
  if tlsEnabled
    http.use_ssl = true
  end

  request = Net::HTTP::Get.new(urlPath)

  response = ''

  if tlsEnabled
    response = Net::HTTP.start(
        urlHost, port,
        :use_ssl => true,
        :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |https|
      https.request(request)
    end
  else
    response = http.request(request)
  end

  failures = getFailures(response)
  if failures.empty?
    send_event(widgetId, { identifier: widgetId, value: 'ok', status: 'available' })
  else
    send_event('alerts', { identifier: widgetId, value: failures.to_s })
    send_event(widgetId, { identifier: widgetId, value: 'danger', status: 'unavailable' })
  end
end

def getFailures(response)
  jsonResponse = JSON.parse(response.body)
  checks = jsonResponse['checks']
  failures = Array.new
  checks.each do |check|
    passed = check['ok']
    unless passed
      failures.push(check['technicalSummary'].to_s)
    end
  end
  failures
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
  performCheckAndSendEventToWidgets('forgot-password-tests-eu', 'ft-memb-user-cred-svc-at-elb-eu-946129326.eu-west-1.elb.amazonaws.com', '/tests/reset-password-critical', false)
  performCheckAndSendEventToWidgets('fastly-tests-eu', 'api-gateway-router-at-eu-prod.herokuapp.com', '/tests', true)
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
  performCheckAndSendEventToWidgets('user-profile-us', 'user-profile-svc-at-lb-us-east-1.memb.ft.com', '/tests/get-profile-critical', true)
  getStatusFromHealthCheck('user-profile-eu', 'http://healthcheck.ft.com', '/service/7b02faa0e45544c26c7f4dddcdafa251', s3oCredentials)
  getStatusFromHealthCheck('user-profile-us', 'http://healthcheck.ft.com', '/service/41ddaf5f7110db4f05cf1104d21c0d78', s3oCredentials)
  getStatusFromHealthCheck('sign-up-app-us', 'http://healthcheck.ft.com', '/service/f3b5a9c8792abcb2ec22000768719f4f', s3oCredentials)
  getStatusFromHealthCheck('offer-api-us', 'http://healthcheck.ft.com', '/service/2ebbedf9134d31785be75f92c4544610', s3oCredentials)
  getStatusFromHealthCheck('offer-api-eu', 'http://healthcheck.ft.com', '/service/7c6b11d53e132a0d4f74e2b4b7886d9f', s3oCredentials)
  getHealth('acc-licence-svc-app2-eu', 'ftaps32892-law1b-eu-p', '/__health', 8443, true)
  getHealth('acc-licence-svc-app1-eu', 'ftaps32893-law1a-eu-p', '/__health', 8443, true)
  getHealth('acc-licence-svc-app2-us', 'ftaps32894-lae1c-us-p', '/__health', 8443, true)
  getHealth('acc-licence-svc-app1-us', 'ftaps32895-lae1a-us-p', '/__health', 8443, true)
  getHealth('acq-context-svc-app1-eu', 'ftaps39084-law1a-eu-p', '/__health', 8443, true)
  getHealth('acq-context-svc-app2-eu', 'ftaps39085-law1b-eu-p', '/__health', 8443, true)
  getHealth('acq-context-svc-app1-us', 'ftaps39364-lae1a-us-p', '/__health', 8443, true)
  getHealth('acq-context-svc-app2-us', 'ftaps39365-lae1c-us-p', '/__health', 8443, true)
  getHealth('barrier-app-app1-eu', 'ftaps32883-law1a-eu-p', '/__health', 8443, true)
  getHealth('barrier-app-app2-eu', 'ftaps33652-law1b-eu-p', '/__health', 8443, true)
  getHealth('barrier-app-app1-us', 'ftaps32884-lae1a-us-p', '/__health', 8443, true)
  getHealth('barrier-app-app2-us', 'ftaps32885-lae1c-us-p', '/__health', 8443, true)
  getHealth('licence-data-svc-app1-eu', 'ftaps48342-law1a-eu-p', '/__health', 8443, true)
  getHealth('licence-data-svc-app2-eu', 'ftaps48343-law1b-eu-p', '/__health', 8443, true)
  getHealth('licence-data-svc-app1-us', 'ftaps48348-lae1a-us-p', '/__health', 8443, true)
  getHealth('licence-data-svc-app2-us', 'ftaps48349-lae1c-us-p', '/__health', 8443, true)
  getHealth('offer-api-app1-eu', 'ftaps64205-law1a-eu-p', '/__health', 8443, true)
  getHealth('offer-api-app2-eu', 'ftaps64206-law1b-eu-p', '/__health', 8443, true)
  getHealth('offer-api-app1-us', 'ftaps64201-lae1a-us-p', '/__health', 8443, true)
  getHealth('offer-api-app2-us', 'ftaps64202-lae1c-us-p', '/__health', 8443, true)
  getHealth('subscription-api-app3-eu', 'ftaps64552-law1a-eu-p', '/__health', 8443, true)
  getHealth('subscription-api-app4-eu', 'ftaps64554-law1b-eu-p', '/__health', 8443, true)
  getHealth('subscription-api-app3-us', 'ftaps64609-lae1a-us-p', '/__health', 8443, true)
  getHealth('subscription-api-app4-us', 'ftaps64610-lae1c-us-p', '/__health', 8443, true)
  getStatusFromNagios('ftmon65099-law1c-eu-p', 'http://ftmon65099-law1c-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon65088-lae1c-us-p', 'http://ftmon65088-lae1c-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon05279-lviw-uk-p', 'http://ftmon05279-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon05323-lvnj-us-p', 'http://ftmon05323-lvnj-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon65099-law1c-eu-p-nagios', 'http://ftmon65099-law1c-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon65088-lae1c-us-p-nagios', 'http://ftmon65088-lae1c-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
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
  getHealth('dam-bridge-eu', 'dam-bridge-euwest1-prod.apps.memb.ft.com', '/__health', 8443, true)
  getHealth('dam-bridge-us', 'dam-bridge-useast1-prod.apps.memb.ft.com', '/__health', 8443, true)
  getHealth('b2b-fulfil-svc-app1-eu', 'ftaps32821-law1a-eu-p', '/__health', 8443, true)
  getHealth('b2b-fulfil-svc-app1-us', 'ftaps63568-lae1c-us-p', '/__health', 8443, true)
  getHealth('b2c-fulfil-svc-app1-eu', 'ftaps42261-law1a-eu-p', '/__health', 8443, true)
  getHealth('b2c-fulfil-svc-app2-eu', 'ftaps42263-law1b-eu-p', '/__health', 8443, true)
  getHealth('b2c-fulfil-svc-app2-us', 'ftaps42558-lae1c-us-p', '/__health', 8443, true)
  getHealth('b2c-fulfil-svc-app1-us', 'ftaps42559-lae1a-us-p', '/__health', 8443, true)
  getHealth('sf-offers-bridge-app1-eu', 'ftaps64081-law1a-eu-p', '/__health', 8443, true)
  getHealth('sf-offers-bridge-app2-eu', 'ftaps64080-law1a-eu-p', '/__health', 8443, true)
end

SCHEDULER.every '45s', first_in: 0 do |job|
  performCheckAndSendEventToWidgets('api-authz-svc-tests-eu', 'api-authz-svc-at-eu-prod.herokuapp.com', '/tests', true)
  performCheckAndSendEventToWidgets('api-authz-svc-tests-us', 'api-authz-svc-at-us-prod.herokuapp.com', '/tests', true)
  performCheckAndSendEventToWidgets('gift-article-svc-tests-eu', 'gift-article-svc-at-eu-prod.herokuapp.com', '/tests', true)
  performCheckAndSendEventToWidgets('session-api-tests-eu', 'ft-memb-session-api-at-elb-p-301208839.eu-west-1.elb.amazonaws.com', '/tests/critical-validate', false)
  getHealth('b2b-signup-app1-eu', 'ftaps40489-law1a-eu-p', '/__health', 8080, false)
  getHealth('b2b-signup-app2-eu', 'ftaps40490-law1b-eu-p', '/__health', 8080, false)
  getHealth('b2b-signup-app1-us', 'ftaps40507-lae1a-us-p', '/__health', 8080, false)
  getHealth('b2b-signup-app2-us', 'ftaps40508-lae1c-us-p', '/__health', 8080, false)
  getHealth('commerce-eml-svc-app1-eu', 'ftaps44665-law1a-eu-p', '/__health', 8443, true)
  getHealth('commerce-eml-svc-app1-us', 'ftaps44666-lae1a-us-p', '/__health', 8443, true)
  getHealth('invoice-svc-app1-eu', 'ftaps44313-law1a-eu-p', '/__health', 8443, true)
  getHealth('invoice-svc-app2-eu', 'ftaps44314-law1b-eu-p', '/__health', 8443, true)
  getHealth('invoice-svc-app1-us', 'ftaps44316-lae1a-us-p', '/__health', 8443, true)
  getHealth('invoice-svc-app2-us', 'ftaps44315-lae1c-us-p', '/__health', 8443, true)
  getHealth('msg-metrics-svc-app2-eu', 'ftaps59377-law1b-eu-p', '/__health', 8443, true)
  getHealth('msg-metrics-svc-app1-us', 'ftaps59378-lae1a-us-p', '/__health', 8443, true)
  getHealth('nwspr-fulfil-svc-app1-eu', 'ftaps51827-lac1a-eu-p', '/__health', 8443, true)
  getHealth('nwspr-fulfil-svc-app2-eu', 'ftaps51828-lac1b-eu-p', '/__health', 8443, true)
  getHealth('nwspr-fulfil-svc-app1-us', 'ftaps52066-lae1a-us-p', '/__health', 8443, true)
  getHealth('nwspr-fulfil-svc-app2-us', 'ftaps52065-lae1c-us-p', '/__health', 8443, true)
  getHealth('redeem-token-svc-app1-eu', 'ftaps38454-law1a-eu-p', '/__health', 8443, true)
  getHealth('redeem-token-svc-app2-eu', 'ftaps38455-law1b-eu-p', '/__health', 8443, true)
  getHealth('redeem-token-svc-app1-us', 'ftaps38467-lae1a-us-p', '/__health', 8443, true)
  getHealth('redeem-token-svc-app2-us', 'ftaps38469-lae1c-us-p', '/__health', 8443, true)
  getHealth('sf-event-bridge-app1-eu', 'ftaps32694-law1a-eu-p', '/__health', 8443, true)
  getHealth('sf-event-bridge-app2-eu', 'ftaps60443-law1b-eu-p', '/__health', 8443, true)
  getHealth('sf-event-bridge-app1-us', 'ftaps32903-lae1a-us-p', '/__health', 8443, true)
  getHealth('zuora-event-bridge-app1-eu', 'ftaps43715-law1a-eu-p', '/__health', 8443, true)
  getHealth('zuora-event-bridge-app2-eu', 'ftaps43716-law1b-eu-p', '/__health', 8443, true)
  getHealth('zuora-event-bridge-app1-us', 'ftaps43713-lae1a-us-p', '/__health', 8443, true)
  getHealth('zuora-event-bridge-app2-us', 'ftaps43714-lae1c-us-p', '/__health', 8443, true)
  getHealth('user-details-svc-app1-eu', 'ftaps64002-law1a-eu-p', '/__health', 8443, true)
  getHealth('user-details-svc-app2-eu', 'ftaps64003-law1b-eu-p', '/__health', 8443, true)
  getHealth('user-details-svc-app1-us', 'ftaps64011-lae1a-us-p', '/__health', 8443, true)
  getHealth('user-details-svc-app2-us', 'ftaps64012-lae1c-us-p', '/__health', 8443, true)
  getStatusFromHealthCheck('anon-email-cont-health', 'http://healthcheck.ft.com', '/service/6b6bdee0040cdc849420e015ba67ca37', s3oCredentials)
  getStatusFromHealthCheck('anon-email-lists-health', 'http://healthcheck.ft.com', '/service/a7cea564191c11812610954d417e102f', s3oCredentials)
  getStatusFromHealthCheck('anon-email-svc-health', 'http://healthcheck.ft.com', '/service/033a5a325be89ebf8e06c84ecee4663c', s3oCredentials)
  getStatusFromHealthCheck('auth-svc-eu-health', 'http://healthcheck.ft.com', '/service/ae1f1f7c47478204cb3d7ccd2f6375c1', s3oCredentials)
  getStatusFromHealthCheck('auth-svc-us-health', 'http://healthcheck.ft.com', '/service/9b178d30c809fce45b591d78dcc28088', s3oCredentials)
  getStatusFromHealthCheck('conker-eu-health', 'http://healthcheck.ft.com', '/service/34ee9011968a45a7055e2bd96be97e04', s3oCredentials)
  getStatusFromHealthCheck('conker-us-health', 'http://healthcheck.ft.com', '/service/ab294b412c9270c4b4b30dd4375e3bc7', s3oCredentials)
  getStatusFromHealthCheck('depr-usr-id-eu-health', 'http://healthcheck.ft.com', '/service/5cda1f9fbc5303a37c3a120c5de2fbfb', s3oCredentials)
  getStatusFromHealthCheck('depr-usr-id-us-health', 'http://healthcheck.ft.com', '/service/75d70bb75e5aced97479302e14c0e643', s3oCredentials)
  getStatusFromHealthCheck('memb-signup-health', 'http://healthcheck.ft.com', '/service/f3b5a9c8792abcb2ec22000768719f4f', s3oCredentials)
  getStatusFromHealthCheck('usr-subs-status-health', 'http://healthcheck.ft.com', '/service/faa0ab90c89e194023ed9c70ff7406f0', s3oCredentials)
  getStatusFromNagios('ftmon33956-law1a-eu-p', 'http://ftmon33956-law1a-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon33953-law1b-eu-p', 'http://ftmon33953-law1b-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon33936-lae1c-us-p', 'http://ftmon33936-lae1c-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon33937-lae1a-us-p', 'http://ftmon33937-lae1a-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon06113-lviw-uk-p', 'http://ftmon06113-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon13667-lvnj-us-p', 'http://ftmon13667-lvnj-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon02464-lviw-uk-p', 'http://ftmon02464-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon05487-lviw-uk-p', 'http://ftmon05487-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon06054-lviw-uk-p', 'http://ftmon06054-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon04625-lviw-uk-p', 'http://ftmon04625-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon06104-lviw-uk-p', 'http://ftmon06104-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon64118-law1a-eu-p', 'http://ftmon64118-law1a-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon64119-law1a-eu-p', 'http://ftmon64119-law1a-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon33953-law1b-eu-p-nagios', 'http://ftmon33953-law1b-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon33936-lae1c-us-p-nagios', 'http://ftmon33936-lae1c-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon33937-lae1a-us-p-nagios', 'http://ftmon33937-lae1a-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon05487-lviw-uk-p-nagios', 'http://ftmon05487-lviw-uk-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon33956-law1a-eu-p-nagios', 'http://ftmon33956-law1a-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon04625-lviw-uk-p-nagios', 'http://ftmon04625-lviw-uk-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon06054-lviw-uk-p-nagios', 'http://ftmon06054-lviw-uk-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon06104-lviw-uk-p-nagios', 'http://ftmon06104-lviw-uk-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
end

SCHEDULER.every '50s', first_in: 0 do |job|
  performCheckAndSendEventToWidgets('cont-acc-tkn-svc-eu', 'cont-acc-tkn-svc-at-eu-prod.herokuapp.com', '/tests', true)
  getHealth('sf-als-sync-svc-app1-eu', 'ftaps60772-law1a-eu-p', '/__health', 8443, true)
  getStatusFromHealthCheck('email-platform-health', 'http://healthcheck.ft.com', '/service/a0a8a8ea4059556e65101fdf6c26624c', s3oCredentials)
  getStatusFromNagios('ftmon32360-lac1a-eu-p', 'http://ftmon32360-lac1a-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon32350-law1a-eu-p', 'http://ftmon32350-law1a-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon32370-lae1a-us-p', 'http://ftmon32370-lae1a-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon05279-lviw-uk-p', 'http://ftmon05279-lviw-uk-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon05323-lvnj-us-p', 'http://ftmon05323-lvnj-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon40924-law1a-eu-p', 'http://ftmon40924-law1a-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon41046-lae1a-us-p', 'http://ftmon41046-lae1a-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon64075-law1a-eu-p', 'http://ftmon64075-law1a-eu-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon64079-lae1a-us-p', 'http://ftmon64079-lae1a-us-p', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon32370-lae1a-us-p-nagios', 'http://ftmon32370-lae1a-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon32360-lac1a-eu-p-nagios', 'http://ftmon32360-lac1a-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon32350-law1a-eu-p-nagios', 'http://ftmon32350-law1a-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon03740-lvnj-us-p-nagios', 'http://ftmon03740-lvnj-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon30057-law1b-eu-t-nagios', 'http://ftmon30057-law1b-eu-t.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon03831-lvpr-uk-int-nagios', 'http://ftmon03831-lvpr-uk-int.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon61265-lae1a-us-p-nagios', 'http://ftmon61265-lae1a-us-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
  getStatusFromNagios('ftmon61266-law1b-eu-p-nagios', 'http://ftmon61266-law1b-eu-p.osb.ft.com', '/nagios/cgi-bin/status.cgi')
end
