# Spirely::Engine.routes.draw — NOT Rails.application.routes.draw. Engine.root
# and Spirely::Application.root (config/application.rb) are the same
# directory in this repo, so Rails::Application's own conventional
# config/routes.rb loading AND this engine's conventional loading both point
# at this exact file; using Rails.application.routes.draw here either drew
# onto the wrong target (nothing reached a Spirely:: controller when mounted
# by a host app — every request silently fell through to the host's own
# catch-all instead) or, once routed through an explicit mount, collided
# ("Invalid route name, already in use") from being loaded twice into the
# same composite route set. Spirely::Engine.routes.draw draws onto exactly
# one target, the engine's own isolated route set, with no double-loading
# possible. Real, but currently untouched, cost of this: Spirely::Application
# (this repo's own standalone-app role, used only by its own dev server) now
# gets zero top-level routes — nothing currently depends on running this
# gem's own dev server directly, so not fixed here; would need genuinely
# separating Engine.root from Application.root (e.g. a real dummy/test app
# directory) to get both roles working from the same repo.
Spirely::Engine.routes.draw do
  # Leading slash — Rails' own built-in health controller, not
  # Spirely::Rails::HealthController, which isolate_namespace would
  # otherwise resolve this to.
  get "/up", to: "/rails/health#show"

  # Everything below is resolved to a specific church via Host header
  # (TenantResolution — verified custom domain, then slug subdomain, then
  # — this gem's own single-tenant fallback — the sole Church row if
  # exactly one exists), not a route constraint.
  #
  # No `scope module: "spirely"` wrapper — isolate_namespace Spirely
  # (lib/spirely/engine.rb) already auto-prepends that module for every
  # controller referenced below (Api::V1::... resolves as
  # Spirely::Api::V1::...); wrapping it again would double up to
  # Spirely::Spirely::....
  namespace :api do
    namespace :v1 do
      resource  :me, only: [:show], controller: "me"

      resource  :family,   only: [:show, :update]
      resources :children, only: [:index, :create, :update, :destroy]
      resources :family_posts, only: [:index, :show, :create, :update, :destroy]

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
          delete :logo, on: :collection, action: :remove_logo
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
        resources :tasks, only: [:index, :show, :create, :update, :destroy]
        resources :family_posts, only: [:index, :show, :destroy] do
          post :approve, on: :member
          post :reject, on: :member
        end
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

  # Ory Hydra login/consent bridge — Hydra redirects here, delegating the
  # actual credential check to Rodauth. See lib/spirely/hydra_client.rb.
  # Bare-HTML (no design investment) — this engine has no frontend of its
  # own. A host app with a real frontend (e.g. spirely-church) shadows this
  # with its own richer bridge/login+consent routes/controllers, declared
  # before it mounts this engine, so those win instead.
  #
  # Lives under Spirely::Bridge:: (not bare top-level Bridge::) for the same
  # isolation reason as everything else here, and so a host app's own
  # top-level Bridge:: controllers never collide with this gem's simpler
  # ones as two different classes claiming the same constant.
  namespace :bridge do
    get "login",          to: "login#show"
    get "login/callback", to: "login#callback"

    get  "consent", to: "consent#show"
    post "consent", to: "consent#create"
  end
end
