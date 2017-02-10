require 'net/http'
require 'json'
require 'date'

# Pull data from Graphite and make available to Dashing Widgets
# Heavily inspired from Thomas Van Machelen's "Bling dashboard article"

graphiteKey = ENV['GRAPHITE_API_KEY'] || ''

# Set the graphite host and port (ip or hostname)
GRAPHITE_URL = 'https://graphite-api.ft.com'
INTERVAL = '15s'

# Job mappings. Define a name and set the metrics name from graphite

job_mapping = {
    #'host1-load-1min' => '*.*.host1.load.onemin',
    'eu-fl-99pc-lat' => 'membership.next.round-trippa.heroku-eu-prod.svc.web.resource-metrics.apache-http-client.requests.fastly.get-requests.p99'
    'eu-gw-99pc-lat' => 'membership.next.round-trippa.heroku-eu-prod.svc.web.resource-metrics.apache-http-client.requests.gateway.get-requests.p99'
    'eu-lb-99pc-lat' => 'membership.next.round-trippa.heroku-eu-prod.svc.web.resource-metrics.apache-http-client.requests.loadbalancer.get-requests.p99'
    'us-fl-99pc-lat' => 'membership.next.round-trippa.heroku-us-prod.svc.web.resource-metrics.apache-http-client.requests.fastly.get-requests.p99'
    'us-gw-99pc-lat' => 'membership.next.round-trippa.heroku-us-prod.svc.web.resource-metrics.apache-http-client.requests.gateway.get-requests.p99'
    'us-lb-99pc-lat' => 'membership.next.round-trippa.heroku-us-prod.svc.web.resource-metrics.apache-http-client.requests.loadbalancer.get-requests.p99'

}

# Extend the float to allow better rounding. Too many digits makes a messy dashboard
class Float
    def sigfig_to_s(digits)
        f = sprintf("%.#{digits - 1}e", self).to_f
        i = f.to_i
        (i == f ? i : f)
    end
end

class Graphite
    # Initialize the class
    def initialize(url)
        @url = url
    end

    # Use Graphite api to query for the stats, parse the returned JSON and return the result
    def query(url, statname, since=nil, graphiteKey)
        since ||= '1h-ago'
        url = URI.parse("#{url}/render?target=#{statname}&format=json&from=#{since}")
        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(url.path, 'Content-Type' =>'application/json')
        request.add_field("key", graphiteKey)
        response = http.request(request)
        return response.body
        # commented out becuase I cant get it to return a json response
        #result = JSON.parse(response.body, :symbolize_names => true)
        #return result
    end

    # Gather the datapoints and turn into Dashing graph widget format
    def points(name, since, graphiteKey)
        stats = query @url, name, since, graphiteKey
        datapoints = stats[:datapoints]

        points = []
        count = 1

        (datapoints.select { |el| not el[0].nil? }).each do|item|
            points << { x: count, y: get_value(item)}
            count += 1
        end

        value = (data.select { |el| not el[0].nil? }).first[0].sigfig_to_s(1)

        return points, value
    end

    def get_value(datapoint)
        values = datapoint[1]
        array = datapoint[1].split(",").map(&:to_i)
        # should return [ latencyValue, epoch timestamp]
        return value
    end

    def value(name, since)
        stats = query @url, name, since
        first = (stats[:datapoints].select { |el| not el[0].nil? }).first[0].sigfig_to_s(0)

        return first
    end
end

job_mapping.each do |title, statname|
   SCHEDULER.every INTERVAL, :first_in => 0 do
        # Create an instance of our Graphite class
        q = Graphite.new GRAPHITE_URL

        # Get the current points and value. Timespan is static atm
        points, current = q.points "#{statname}", "-1min", graphiteKey

        # Send to dashboard, tested supports for number, meter and graph widgets
        send_event "eu-fl-99pc-lat", { value: current }
   end
end
