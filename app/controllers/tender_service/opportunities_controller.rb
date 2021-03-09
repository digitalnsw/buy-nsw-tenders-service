require_dependency "tender_service/application_controller"
require 'set'
require 'json'
require 'nokogiri'

module TenderService
  class OpportunitiesController < TenderService::ApplicationController
    include SharedModules::Serializer

    # before_action :authenticate_user, only: [:index]

    def search 

      page = (params[:page] || 1).to_i
      page = 1 unless page > 1
      rpp = params[:rpp].to_i
      rpp = 10 unless rpp >= 10 && rpp <= 100

      # perform a cloudsearch search
      client = Aws::CloudSearchDomain::Client.new(
        credentials: Aws::Credentials.new(ENV['CLOUDSEARCH_AWS_ACCESS_KEY_ID'], ENV['CLOUDSEARCH_AWS_SECRET_ACCESS_KEY']), 
        region: 'ap-southeast-2', 
        endpoint: ENV['CLOUDSEARCH_DOMAIN_OPPS_SEARCH']
      )

      params[:term] = (params[:term] || '')
      queryTerms = ''
      if !params[:term].empty?
        params[:term].split(' ').each do |item|
          queryTerms += "(term field=title \'#{item}\') (term field=short_description \'#{item}\')"
        end
        queryTerms = "(or #{queryTerms})"
      else
        queryTerms = 'matchall'
      end

      sortOrder = 'late_close_date asc'
      if queryTerms != 'matchall'
        sortOrder = '_score asc, late_close_date asc'
      elsif params[:order] == 'closeAsc'
        sortOrder = 'late_close_date asc'
      elsif params[:order] == 'closeDesc'
        sortOrder = 'late_close_date desc'
      end

      filterDateRange = "(range field=late_close_date [\'#{DateTime.now().strftime('%Y-%m-%dT%H:%M:%SZ')}\',})"

      params[:services] = (params[:services] || [])
      serviceCategory = ''
      if params[:services].length > 0
        params[:services].each do |item|
          serviceCategory += "(or field=category \'#{item}\')"
        end
        serviceCategory = "(or #{serviceCategory})"
      end

      params[:opptypes] = (params[:opptypes] || [])
      filterOppType = ''
      if params[:opptypes].length > 0
        params[:opptypes].each do |item|
          filterOppType += "(or field=opportunity_type \'#{item}\')"
        end
        filterOppType = "(or #{filterOppType})"
      end


      resp = client.search(
        query: "(or #{queryTerms})", 
        filter_query: "(and #{filterDateRange} #{serviceCategory} #{filterOppType})", 
        query_options: "{fields:['title^3','short_description^2']}",
        query_parser: 'structured',
        size: rpp,
        start: (page-1)*rpp,
        sort: sortOrder
      )
      # puts resp.hits.to_json

      results = []
      # map the hits hash (where values are arrays of strings) to a results hash (where values are just a string)
      resp.hits.hit.each do |item|
        hash = item.fields
        hash.map { |k,v| 
          hash[k] = v[0]
        }
        hash[:id] = item.id
        results.append hash
        # puts hash
      end

      found = (resp.hits.found || 0)

      render json: { opportunities: full_sanitize_recursive(results), meta: { totalCount: found } }
    end  

    def count 
      client = Aws::CloudSearchDomain::Client.new(
        credentials: Aws::Credentials.new(ENV['CLOUDSEARCH_AWS_ACCESS_KEY_ID'], ENV['CLOUDSEARCH_AWS_SECRET_ACCESS_KEY']), 
        region: 'ap-southeast-2', 
        endpoint: ENV['CLOUDSEARCH_DOMAIN_OPPS_SEARCH']
      )

      filterDateRange = "(range field=late_close_date [\'#{DateTime.now.strftime('%Y-%m-%dT%H:%M:%SZ')}\',})"
      resp = client.search(
        query: 'matchall', 
        filter_query: "(and #{filterDateRange})", 
        query_parser: 'structured',
        return: '_no_fields',
      )
      globalFound = resp.hits.found

      render json: {
        globalCount: globalFound,
      }
    end      

  end
end
