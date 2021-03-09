TenderService::Engine.routes.draw do
  resources :tenders, only: [:index]

  # resources :opportunities, only: [:index, :show] do
  resources :opportunities, only: [:index] do
    get :search, on: :collection
    get :uploadtenders, on: :collection
    get :deletetenders, on: :collection
    get :count, on: :collection
  end

end
