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

    def self.categories
      {
        "community-and-social-services" => [
          '9314',
        ],
        "construction" => [
          '14111610',
          '22',
          '22101716',
          '30',
          '3019',
          '30191616',
          '30191617',
          '301917',
          '30191701',
          '30191702',
          '30111902',
          '60106102',
          '60141302',
          '72151201',
          '721417',
          '72141701',
          '72141702',
          '72153505',
          '72153507',
          '73161505',
        ],
        "educational-supplies" => [
          '60',
          '432325',
          '55101509',
          '55111515',
          '601012',
          '601013',
          '601016',
          '60141101',
          '81112216',
          '861118',
          '86111801',
          '86111802',
          '8612',
          '8614',
          '861415',
          '86141501',
          '861417',
          '94100607',
          '94111903',
          '951219',
        ],
        "engineering-research-and-technology-services" => [
          '81',
        ],
        "fleet-management" => [
          '80161505',
        ],
        "food" => [
          '50',
          '90',
          '111417',
          '11141701',
          '121645',
          '12171504',
          '231815',
          '23181518',
          '231816',
          '231817',
          '23181705',
          '23201204',
          '24121804',
          '40142012',
          '41116118',
          '41116119',
          '42211910',
          '42211911',
          '47131833',
        ],
        "healthcare-services" => [
          '85',
        ],
        "recruitment-and-human-resources" => [
          '43231505',
          '8011',
          '80111505',
          '80111620',
        ],
        "information-communications-technology" => [
          '4300',
          '80101507',
          '8116',
          '4320',
          '80111608',
          '80111609',
          '80111610',
          '80111711',
          '80111610',
          '80111711',
          '80111712',
          '80111713',
          '80111716',
          '4321',
          '4322',
          '4323',
        ],
        "marketing-and-advertising" => [
          '8014',
          '80141501',
          '80141505',
          '60155409',
          '80171915',
          '8210',
          '55121901',
          '60105409',
        ],
        "office-supplies-and-services" => [
          '4412',
        ],
        "professional-services" => [
          '80',
          '80101706',
          '8110',
          '8215',
        ],
        "property-management-and-maintenance" => [
          '80131801',
          '80161601',
          '7200',
          '8310',
        ],
        "travel" => [
          '9012',
          '2511',
          '7810',
        ],
      }
    end

    attr_reader :score

    def score calc_services
      @score ||= services.map{|s|self.class.categories[s] || []}.flatten.map{|code|
        fields['UNSPSCCode'].starts_with?(code) ? (code.length ** 2) : 0
      }.sum
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
