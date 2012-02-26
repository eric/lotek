require 'sinatra'
require 'active_support'
require 'librato_metrics'
require 'line_parser'

module Lotek
  class App < Sinatra::Base
    configure do
      set :public_folder, Proc.new { File.join(root, "public") }
      set :cache, lambda { Dalli::Client.new }
      set :metrics_client, LibratoMetrics.new(ENV['METRICS_EMAIL'], ENV['METRICS_TOKEN'])
    end

    get '/' do
      erb :index
    end

    post '/preview' do
      parser = LineParser.new(params)
      lines = params[:lines].split(/\n+/)

      @variable_list = lines.collect do |line|
        parser.parse_message(line)
      end

      @keys = @variable_list.first.keys.sort

      result = parser.parse(:hostname => 'host1', :message => lines.first)

      @metric = result[:metric]
      @source = result[:source]

      erb :preview, :layout => false
    end

    post '/submit' do
      payload = HashWithIndifferentAccess.new(Yajl::Parser.parse(params[:payload]))
      parser  = LineParser.new(params)

      queue = MetricQueue.new(settings.cache, 60)

      payload[:events].each do |event|
        if data = parser.parse(event)
          case data[:aggregation]
          when 'average'
            queue.average_gauge(data[:name], data[:time], data[:source], data[:value])
          when 'sum'
            queue.sum_gauge(data[:name], data[:time], data[:source], data[:value])
          when 'count'
            queue.sum_gauge(data[:name], data[:time], data[:source], 1)
          end
        end
      end

      queue.save

      settings.metrics_client.submit(queue.to_hash)

      'ok'
    end
  end
end