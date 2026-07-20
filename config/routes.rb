Rails.application.routes.draw do
  get "/up", to: "rails/health#show"

  scope module: "spirely" do
    namespace :api do
      namespace :v1 do
        resource  :family,   only: [:show, :update]
        resources :children, only: [:index, :create, :update, :destroy]
        resource  :sync_settings, only: [:show, :update]
        post "/sync/trigger", to: "sync#trigger"

        namespace :admin do
          resource  :stats,      only: [:show]
          resource  :config,     only: [:show]
          resource  :pco_status, only: [:show]
          resources :families,   only: [:index, :show, :create] do
            post :invite, on: :member
          end
        end

        resources :invitations, only: [:show], param: :token do
          post :accept, on: :member
        end
      end
    end

    namespace :auth do
      get "pco/connect",  to: "pco#connect"
      get "pco/callback", to: "pco#callback"
    end
  end

  # Ory Hydra login/consent bridge — Hydra redirects here, delegating the
  # actual credential check to Rodauth. See lib/spirely/hydra_client.rb.
  namespace :bridge do
    get "login",          to: "login#show"
    get "login/callback", to: "login#callback"

    get  "consent", to: "consent#show"
    post "consent", to: "consent#create"
  end
end
