module TenantResolution
  extend ActiveSupport::Concern

  included do
    before_action :resolve_tenant!
  end

  private

  # Resolves which church a request belongs to from the Host header — checks
  # verified custom domains first, then falls back to the free default
  # {slug}.spirely.cloud-style subdomain, then — spirely-church only, added
  # in the SaaS-only subtraction pass — the sole Church row if neither
  # matched. Deliberately not a route-level constraint: custom domains
  # can't be pattern-matched at the routes layer the way the "manage"
  # subdomain can (spirely-cloud only), so this always runs at the
  # controller layer for every tenant-facing request.
  def resolve_tenant!
    Current.church =
      CustomDomain.where.not(verified_at: nil).find_by(hostname: request.host)&.church ||
      Church.find_by(slug: request.subdomain) ||
      sole_church_fallback
  end

  # spirely-church is single-tenant by design (see
  # lib/tasks/spirely_cloud.rake — the one operator-run way to create its
  # one Church row). Without this, a fresh self-hosted install 404s on
  # every request until an operator finishes subdomain/custom-domain
  # configuration it may not even want — this lets it work immediately at
  # whatever hostname it's reached on (localhost, a bare IP, a Railway-
  # generated domain, a real domain before DNS is fully wired up).
  #
  # Only ever applies with EXACTLY one Church row. With zero, there's
  # nothing to fall back to. With two or more, silently guessing which
  # tenant a request belongs to would be a real cross-tenant data leak,
  # not a convenience — that's a genuinely multi-tenant deployment and
  # needs real Host-based resolution configured, same as spirely-cloud.
  def sole_church_fallback
    Church.sole
  rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
    nil
  end

  # Include alongside TenantResolution in any controller that should 404 for
  # unrecognized hosts rather than silently proceeding with Current.church
  # == nil (e.g. the "manage." surface deliberately does NOT include this,
  # since it resolves its own tenant context via session, not Host header).
  def require_tenant!
    return if Current.church

    # Not `respond_to` — ActionController::API (used by the JSON controllers
    # sharing this concern) doesn't include ActionController::MimeResponds.
    if request.format.json?
      render json: { error: "Not found", code: "not_found" }, status: :not_found
    else
      head :not_found
    end
  end
end
