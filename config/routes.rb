Rails.application.routes.draw do
  get "/up", to: "rails/health#show"

  # Everything below is resolved to a specific church via Host header
  # (TenantResolution — verified custom domain, then slug subdomain, then
  # — this gem's own single-tenant fallback — the sole Church row if
  # exactly one exists), not a route constraint.
  scope module: "spirely" do
    namespace :api do
      namespace :v1 do
        resource  :me, only: [:show], controller: "me"

        resource  :family,   only: [:show, :update]
        resources :children, only: [:index, :create, :update, :destroy]

        resource  :sync_settings, only: [:show, :update]
        post "/sync/trigger", to: "sync#trigger"

        namespace :admin do
          resource  :stats,      only: [:show]
          # `controller:` overrides needed — Rails' default pluralization for
          # a singular `resource` route expects a plural controller
          # (ConfigsController, PcoStatusesController), which doesn't match
          # the actual singular ConfigController/PcoStatusController classes.
          resource  :config,     only: [:show, :update], controller: "config" do
            get :connect_url
          end
          resource  :pco_status, only: [:show], controller: "pco_status"
          resource  :twilio_verification, only: [:create], controller: "twilio_verification" do
            post :confirm, on: :collection
          end
          resources :families, only: [:index, :show, :create] do
            post :invite, on: :member
            resources :guardians, only: [], controller: "guardian_invitations" do
              post :invite, on: :member
            end
          end
          resource  :staff, only: [:show], controller: "staff"
          resources :staff_invitations, only: [:create]
        end

        resources :invitations, only: [:show], param: :token do
          post :accept, on: :member
        end
        resources :staff_invitations, only: [:show], param: :token do
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
