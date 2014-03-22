require 'elasticsearch'

module Forklift
  module Connection
    class Elasticsearch < Forklift::Base::Connection

      def initialize(config, forklift)
        @config = config
        @forklift = forklift
        @client = ::Elasticsearch::Client.new(config)
      end

      def config
        @config
      end

      def forklift
        @forklift
      end

      def read(index, query, looping=true, from=0, size=1000)
        offset = 0
        while (looping == true)
          data = []
          prepared_query = query
          prepared_query[:from] = from + offset
          prepared_query[:size] = size
          
          results = client.search( { index: index, body: prepared_query } )
          results["hits"]["hits"].each do |hit|
            data << hit["_source"]
          end

          if block_given?
            yield data 
          else
            return data
          end

          looping = false if results["hits"]["hits"].length == 0
          offset = offset + size
        end
      end

      def write(data, index, update=false, type='forklift', primary_key=:id)
        data.each do |d|
          object = {
            :index => index,
            :body  => d,
            :type  => type,
          }
          object[:id] = d[primary_key] if ( !d[primary_key].nil? && update == true )
          client.index object
        end
      end

      def delete_index(index)
        client.indices.delete({ :index => index }) if client.indices.exists({ :index => index })
      end

      private

      #/private

    end
  end
end