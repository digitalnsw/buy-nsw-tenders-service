module TenderService
  class TendersImportJob < SharedModules::ApplicationJob
    def perform(document)
      file = download_file(document)
      xml_doc = Nokogiri::XML(File.open(file))
      TenderService::Tender.import(xml_doc)
      document.update_attributes!(after_scan: nil)

      deletetenders
      uploadtenders
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

      return
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
      # puts resp.to_a

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
      # puts resp.to_a

      return
    end  

  end
end
