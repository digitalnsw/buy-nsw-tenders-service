module TenderService
  class Tender < ApplicationRecord
    self.table_name = 'tenders'
    acts_as_paranoid column: :discarded_at

    def self.valid_fields
      {
        'TenderUUID' => :tender_uuid,
        'AgencyName' => :agency_name,
        'AgencyLevel1Name' => :agency_level_1_name,
        'TenderTypeTitle' => :tender_type,
        'UNSPSCCode' => :unspsc_code,
        'UNSPSCCodeAdditional' => :unspsc_code_additional,
        'Title' => :title,
        'LateCloseDateTime' => :late_close_date,
        'CloseDateTime' => :close_date,
        'PublishDate' => :publish_date,
        'ShortDescription' => :short_description,
        'LongDescription' => :long_description,
        'ContactName' => :contact_name,
        'ContactPhone' => :contact_phone,
        'ContactEmail' => :contact_email,
      }
    end

    def self.ict_categories
      {
        "cloud-services" => [
          # "81112106",
          # "8312XXXX",

          "4321XXXX",
          "4322XXXX",
          "4323XXXX",
          "8110XXXX",
          "8116XXXX",
        ],
        "software-development" => [
          # "432324XX",
          # "81111503",

          "8110XXXX",
        ],
        "software-licensing" => [
          # "4323XXXX",
          # "8116XXXX",

          "4323XXXX",
        ],
        "end-user-computing" => [
          # "43211507",
          # "43211506",
          # "43211503",
          # "43211509",
          # "441015XX",
          # "432119XX",
          # "432116XX",
          # "81112307",
          # "8111XXXX",

          "4319XXXX",
          "4320XXXX",
          "4321XXXX",
          "8016XXXX",
          "8110XXXX",
        ],
        "infrastructure" => [
          # "43222628",
          # "432226XX",
          # "43223308",
          # "39121011",
          # "43222609",
          # "2610XXXX",
          # "43222642",
          # "3213XXXX",
          # "3215XXXX",

          "4321XXXX",
          "4322XXXX",
          "8116XXXX",
          "8311XXXX",
          "8312XXXX",
        ],
        "telecommunications" => [
          # "431915XX",
          # "43191501",
          # "43191504",
          # "4320XXXX",
          # "4321XXXX",
          # "4322XXXX",
          # "4323XXXX",

          "4319XXXX",
          "4322XXXX",
          "8116XXXX",
          "8311XXXX",
          "8312XXXX",
        ],
        "managed-services" => [
          # "81112003",
          # "8010XXXX",
          # "8012XXXX",
          # "8013XXXX",
          # "8014XXXX",
          # "8015XXXX",
          # "8016XXXX",
          # "8017XXXX",

          "4322XXXX",
          "8110XXXX",
          "8116XXXX",
        ],
        "advisory-consulting" => [
          # "80101505",
          # "80101507",

          "8010XXXX",
          "8016XXXX",
        ],
      }
    end


    def score services
      services.map{|s|self.class.ict_categories[s] || []}.flatten.map{|code|
        (1..3).map{|i| code[0..i*2+1] == fields["UNSPSCCode"][0..i*2+1] ? i : 0}.max
      }.max.to_i * 100 + rand(100)
    end

    def current?
      fields['CancelledByUserUUID'].blank?
    end

    def set_close_time
      self.closed_at = DateTime.parse(fields['CloseDateTime']) rescue DateTime.now
      self.late_closed_at = DateTime.parse(fields['LateCloseDateTime']) rescue closed_at
    end

    def serialize
      hash = self.class.valid_fields.map{ |k,v|
        [v, fields[k]]
      }.to_h
      hash[:id] = id
      hash[:category] = TenderService::UnspscCode.where(code: fields['UNSPSCCode']).first&.description || fields['UNSPSCCode']
      hash[:short_description] = ActionView::Base.full_sanitizer.sanitize(hash[:short_description], tags: []) rescue nil
      hash[:long_description] = ActionView::Base.full_sanitizer.sanitize(hash[:long_description], tags: []) rescue nil
      hash
    end

    def self.import doc
      doc.css("row").each do |row|
        fields = row.css("field").map do |field|
          [field['name'], field.inner_text]
        end.compact.to_h
        tender = TenderService::Tender.find_or_initialize_by(uuid: fields['TenderUUID'])
        tender.fields = fields
        tender.set_close_time
        tender.save!
      end
    end
  end
end
