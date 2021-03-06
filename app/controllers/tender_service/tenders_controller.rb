require_dependency "tender_service/application_controller"
require 'set'
require 'json'
require 'nokogiri'

module TenderService
  class TendersController < TenderService::ApplicationController
    include SharedModules::Serializer

    before_action :authenticate_user, only: [:index]

    def index
      services = []
      if session_user&.seller_id.present?
        services = SharedResources::RemoteSeller.all_services(session_user.seller_id).to_a
      end
      services = TenderService::Tender.categories.keys if services.blank?
      tenders = TenderService::Tender.where('late_closed_at > now()').
        order(late_closed_at: :desc).to_a.select(&:current?).
        sort_by{|t| - t.calc_score(services)}[0..2].select{|t|t.score.positive?}
      render json: { tenders: full_sanitize_recursive(tenders.map(&:serialize)) }
    end
  end
end
