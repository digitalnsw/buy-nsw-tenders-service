TenderService::Engine.routes.draw do
  resources :tenders, only: [:index]
end
