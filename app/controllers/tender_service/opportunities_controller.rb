require_dependency "tender_service/application_controller"
require 'set'
require 'json'
require 'nokogiri'

module TenderService
  class OpportunitiesController < TenderService::ApplicationController
    include SharedModules::Serializer

    # before_action :authenticate_user, only: [:index]

    def index
      
      # only useful if automatically filtering/sorting by the services tied to the supplier,
      # otherwise just filter by what is selected in the UI->API request
    #   services = []
    #   if session_user&.seller_id.present?
    #     services = SharedResources::RemoteSeller.all_services(session_user.seller_id).to_a
    #   end
    #   services = TenderService::Tender.categories.keys if services.blank?

        page = (params[:page] || 1).to_i
        rpp = params[:rpp].to_i

        rpp = 10 unless rpp >= 10 && rpp <= 100

        tenders = TenderService::Tender.where('late_closed_at > now()')

        # note: cannot test any filtering while Tenders data is stored in json column

        if params[:order] == 'closeDesc'
            tenders = tenders.order(late_closed_at: :desc)
        elsif params[:order] == 'lastUpdate'
            tenders = tenders.order(updated_at: :desc)
        else
            tenders = tenders.order(late_closed_at: :asc)
        end

        tenders = tenders.
                offset( (page-1) * rpp ).
                limit(rpp)
       
        render json: { opportunities: full_sanitize_recursive(tenders.map(&:serialize)) }

    end


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


    def uploadtenders

      client = Aws::CloudSearchDomain::Client.new(
        credentials: Aws::Credentials.new(ENV['CLOUDSEARCH_AWS_ACCESS_KEY_ID'], ENV['CLOUDSEARCH_AWS_SECRET_ACCESS_KEY']), 
        region: 'ap-southeast-2', 
        endpoint: ENV['CLOUDSEARCH_DOMAIN_OPPS_DOCUMENT']
      )

      tenders = TenderService::Tender.where('late_closed_at > now()')
      docs = []

      tenders.each do |tender|
        tender = tender.serialize

        next if tender[:late_close_date].nil? || tender[:late_close_date].length == 0

        category_scores = TenderService::Tender.categories.map { |k,v| 
          [
            k, 
            TenderService::Tender.categories[k].map{ |code|
              tender[:unspsc_code].starts_with?(code) ? code.length : 0
            }.sum
          ]
        }.select { |item| item[1] > 0}.sort_by{ |k, v| v }.reverse
        category_name = category_scores.length > 0 ? category_scores.first[0] : ''

        opptype = {
          "Open Tenders": "tender",
          "Scheme Invitation": "scheme",
          "Panel": "panel",
          "Expression of Interest": "eoi",
        }

        doc = {
          type: "add",
          id: "tenders-#{tender[:tender_uuid]}",
          fields: {
            external_uuid: tender[:tender_uuid],
            agency_name: tender[:agency_name],
            opportunity_type: opptype.key?(tender[:tender_type].to_sym) ? opptype[tender[:tender_type].to_sym] : '',
            unspsc_code: tender[:unspsc_code],
            title: tender[:title],
            opportunity_number: tender[:number],
            late_close_date: DateTime.parse(tender[:late_close_date]).strftime('%Y-%m-%dT%H:%M:%SZ'),
            close_date: DateTime.parse(tender[:close_date]).strftime('%Y-%m-%dT%H:%M:%SZ'),
            publish_date: DateTime.parse(tender[:publish_date]).strftime('%Y-%m-%dT%H:%M:%SZ'),
            short_description: tender[:short_description],
            long_description: tender[:long_description],
            external_category: tender[:category],
            category: category_name,
            source: "tenders"
          }
        }
        docs.append doc
      end
      # puts ">>>>>>"
      # puts docs
      # puts "<<<<<<"

      resp = client.upload_documents({documents: docs.to_json, content_type: "application/json"})
      # puts resp.to_a

      render json: { uploadedtenders: true }
    end  


    def deletetenders

      client = Aws::CloudSearchDomain::Client.new(
        credentials: Aws::Credentials.new(ENV['CLOUDSEARCH_AWS_ACCESS_KEY_ID'], ENV['CLOUDSEARCH_AWS_SECRET_ACCESS_KEY']), 
        region: 'ap-southeast-2', 
        endpoint: ENV['CLOUDSEARCH_DOMAIN_OPPS_SEARCH']
      )

      resp = client.search(
        query: '(or field=source \'tenders\')', 
        query_parser: 'structured',
        return: '_no_fields',
        size: 1000,
      )
      puts resp.to_a

      client = Aws::CloudSearchDomain::Client.new(
        credentials: Aws::Credentials.new(ENV['CLOUDSEARCH_AWS_ACCESS_KEY_ID'], ENV['CLOUDSEARCH_AWS_SECRET_ACCESS_KEY']), 
        region: 'ap-southeast-2', 
        endpoint: ENV['CLOUDSEARCH_DOMAIN_OPPS_DOCUMENT']
      )

      docs = []

      resp.hits.hit.each do |item|
        doc = {
          type: "delete",
          id: item.id,
        }
        docs.append doc
      end

      resp = client.upload_documents({documents: docs.to_json, content_type: "application/json"})
      puts resp.to_a

      render json: { deletedtenders: true }
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
