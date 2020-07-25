Rails.application.routes.draw do
  mount TenderService::Engine => "/tender_service"
end
