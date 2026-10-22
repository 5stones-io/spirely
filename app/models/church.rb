class Church < ApplicationRecord
  # Ministry modules a church can turn on (Church#enabled_modules). Keys
  # are the stored/API ids; label is what admins see in Settings and
  # onboarding. Adding a module is one entry here plus its own
  # require_module!-gated code.
  MODULES = {
    "kidsmin"     => { label: "Kids Ministry" },
    "smallgroups" => { label: "Small Groups" },
    "kudos"       => { label: "Kudos" },
  }.freeze
  KNOWN_MODULES = MODULES.keys.freeze
  # Modules that use the shared Planning Center Groups data (Spirely::Group
  # & co). Kids Ministry doesn't need its own entry: on a kids-only domain
  # it gets Small Groups limited to children's groups (#children_groups_only?).
  GROUP_MODULES = %w[smallgroups].freeze
  STATUSES = %w[pending approved suspended].freeze
  # Two hand-built Lovable-designed looks for the Public Mini-Site
  # (Home/About/Events) — "default" is the original kidspire-ported
  # design, "v2" a second full design Chad generated separately
  # (samples/{home,about,events}-theme-v2.html). Not the AI-generated
  # per-church theming pipeline described in CLAUDE.md's "Planned:
  # per-church module theming/skins" — that's a different, much bigger,
  # still-unbuilt feature; this is just a fixed pick-one-of-two toggle.
  PUBLIC_SITE_THEMES = %w[default v2].freeze

  # Inherited from spirely-cloud's SaaS signup flow (ChurchProvisioner
  # assigns "tmp-<uuid>" when no real slug is given, later claimed via a
  # manage.-subdomain onboarding wizard) — that whole flow was forked out
  # of spirely-church (see CLAUDE.md's SaaS-only subtraction pass), so
  # this sentinel is currently vestigial here: the rake task that creates
  # a spirely-church install's one Church always passes a real slug
  # explicitly. Left in place rather than removed — harmless, and Church
  # #slug's own format/uniqueness validations don't depend on it either
  # way.
  TMP_SLUG_PREFIX = "tmp-"

  has_many :memberships, dependent: :destroy
  has_many :accounts, through: :memberships
  has_many :custom_domains, dependent: :destroy
  has_many :families, class_name: "Spirely::Family", dependent: :destroy
  has_many :children, class_name: "Spirely::Child", dependent: :destroy
  has_many :guardians, class_name: "Spirely::Guardian", dependent: :destroy
  has_many :invitations, class_name: "Spirely::Invitation", dependent: :destroy
  has_many :staff_invitations, class_name: "Spirely::StaffInvitation", dependent: :destroy
  has_many :people, class_name: "Spirely::Person", dependent: :destroy
  has_many :volunteer_profiles, class_name: "Spirely::VolunteerProfile", dependent: :destroy
  has_many :attendances, class_name: "Spirely::Attendance", dependent: :destroy
  has_many :locations, class_name: "Spirely::Location", dependent: :destroy
  has_many :attendance_nudges, class_name: "Spirely::AttendanceNudge", dependent: :destroy
  has_many :contact_notes, class_name: "Spirely::ContactNote", dependent: :destroy
  has_many :events, class_name: "Spirely::Event", dependent: :destroy
  has_many :incidents, class_name: "Spirely::Incident", dependent: :destroy
  has_many :announcements, class_name: "Spirely::Announcement", dependent: :destroy
  has_many :pco_data_error_statuses, class_name: "Spirely::PcoDataErrorStatus", dependent: :destroy
  has_many :registration_statuses, class_name: "Spirely::RegistrationStatus", dependent: :destroy
  has_many :tasks, class_name: "Spirely::Task", dependent: :destroy
  has_many :family_posts, class_name: "Spirely::FamilyPost", dependent: :destroy
  has_many :group_types, class_name: "Spirely::GroupType", dependent: :destroy
  has_many :groups, class_name: "Spirely::Group", dependent: :destroy
  has_many :group_memberships, class_name: "Spirely::GroupMembership", dependent: :destroy
  has_many :group_events, class_name: "Spirely::GroupEvent", dependent: :destroy
  has_many :group_attendances, class_name: "Spirely::GroupAttendance", dependent: :destroy
  has_many :group_applications, class_name: "Spirely::GroupApplication", dependent: :destroy
  has_many :group_schedule_assignments, class_name: "Spirely::GroupScheduleAssignment", dependent: :destroy
  has_many :group_nudges, class_name: "Spirely::GroupNudge", dependent: :destroy
  has_many :points_entries, class_name: "Spirely::PointsEntry", dependent: :destroy
  has_one  :kudos_setting, class_name: "Spirely::KudosSetting", dependent: :destroy
  has_many :promo_codes, class_name: "Spirely::PromoCode", dependent: :destroy
  has_many :service_types, class_name: "Spirely::ServiceType", dependent: :destroy
  has_many :store_orders, class_name: "Spirely::StoreOrder", dependent: :delete_all
  has_many :store_codes, class_name: "Spirely::StoreCode", dependent: :delete_all
  has_many :store_items, class_name: "Spirely::StoreItem", dependent: :destroy
  has_many :service_plans, class_name: "Spirely::ServicePlan"
  has_many :service_plan_people, class_name: "Spirely::ServicePlanPerson"
  has_one  :church_integration, class_name: "Spirely::ChurchIntegration", dependent: :destroy
  has_one  :sync_setting, class_name: "Spirely::SyncSetting", dependent: :destroy

  # App-shell brand mark (sidebar/mobile top bar logo + wordmark) — lets a
  # church make that corner look like their own. Not the AI-generated
  # per-church module theming pipeline described in CLAUDE.md's "Planned"
  # section (a much bigger, still-unbuilt feature); this is just a static
  # logo + display name a church sets once in Settings.
  has_one_attached :logo

  MAX_LOGO_SIZE = 2.megabytes
  ALLOWED_LOGO_TYPES = %w[image/png image/jpeg image/svg+xml image/webp].freeze

  # How the app shell renders whatever's in `logo` — a church picks this
  # in Settings alongside the upload itself. "circle"/"square" both crop
  # to a fixed square (object-cover) at different corner roundedness;
  # "rectangle" doesn't crop at all (object-contain, no forced aspect
  # ratio) — for a wide wordmark-style logo a square crop would cut into.
  LOGO_SHAPES = %w[circle square rectangle].freeze

  validate :logo_within_size_and_type_limits

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?\z/, message: "must be lowercase letters, numbers, and hyphens" }
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :public_site_theme, inclusion: { in: PUBLIC_SITE_THEMES }
  validates :logo_shape, inclusion: { in: LOGO_SHAPES }

  # The modules this request can use: everything the church has on,
  # narrowed to the custom domain's own list when the request came in on a
  # module-scoped domain (5ST-12) — e.g. only "smallgroups" on
  # portal.jccag.org. Outside a request (jobs, console) there's no domain,
  # so this is just enabled_modules — the groups sync still runs.
  #
  # A kids-only domain also gets Small Groups when the church has it on
  # (5ST-57), limited to children's groups — see #children_groups_only?.
  def active_modules
    domain = current_domain
    return enabled_modules unless domain&.restricted?

    shown = domain.modules
    shown |= ["smallgroups"] if shown.include?("kidsmin")
    enabled_modules & shown
  end

  def module_enabled?(name)
    active_modules.include?(name.to_s)
  end

  # True when any module that uses Planning Center Groups is on — gates
  # the groups sync and the shared group endpoints.
  def uses_groups?
    (active_modules & GROUP_MODULES).any?
  end

  # True on a module-scoped domain that has Small Groups only through Kids
  # Ministry (5ST-57): its group screens show children's groups only.
  def children_groups_only?
    domain = current_domain
    !!domain&.restricted? && !domain.modules.include?("smallgroups")
  end

  # The groups this request can see — every group, or only those whose
  # group type is marked children on a kids-only domain. Group endpoints
  # read through this (and #visible_group_nudges), never #groups directly.
  def visible_groups
    return groups unless children_groups_only?

    groups.joins(:group_type).where(spirely_group_types: { audience: "children" })
  end

  def visible_group_nudges
    return group_nudges unless children_groups_only?

    group_nudges.where(group_id: visible_groups.select(:id))
  end

  # Where links for one module's features should point (e.g. Small Groups
  # schedule emails): a verified domain scoped to that module, else the
  # primary domain if it serves the module, else any unrestricted verified
  # domain, else the church's default host.
  def hostname_for_module(name)
    verified = custom_domains.select(&:verified?)
    primary  = verified.find(&:primary?)
    domain = verified.find { |d| d.restricted? && d.serves_module?(name) } ||
             (primary if primary&.serves_module?(name)) ||
             verified.find { |d| !d.restricted? }
    domain&.hostname || default_hostname
  end

  # What the app shell's brand mark actually shows — falls back to the
  # church's real `name` when no shorter display_name has been set.
  # A module-scoped domain with its own display_name (5ST-12) overrides the
  # church-wide branding for requests on that domain.
  def brand_name
    current_domain&.display_name.presence || display_name.presence || name
  end

  # The logo the app shell shows on this request's domain — a domain with
  # its own branding only ever shows its own logo (nil = initial mark).
  def active_logo
    domain = current_domain
    return (domain.logo.attached? ? domain.logo : nil) if domain&.own_branding?
    logo.attached? ? logo : nil
  end

  def active_logo_shape
    current_domain&.logo_shape.presence || logo_shape
  end

  def placeholder_slug?
    slug.start_with?(TMP_SLUG_PREFIX)
  end

  def pending?
    status == "pending"
  end

  def suspended?
    status == "suspended"
  end

  def approve!
    update!(status: "approved")
  end

  # Inherited from spirely-cloud, where spirely.io (billing) called this
  # via the now-removed Platform::ChurchesController#suspend on a lapsed
  # subscription. No caller in spirely-church today — there's no billing
  # here — but left in place as a plain operator-usable kill switch (a
  # self-hoster can still call this from a console/rake task if needed).
  def suspend!
    update!(status: "suspended")
  end

  # The custom domain a church has designated as primary, if verified; falls
  # back to APP_HOST (this deployment's own host — a self-hoster sets this
  # once, e.g. "kids.mychurch.org" or a Railway-issued domain) otherwise.
  # Unlike spirely-cloud (many churches, one deployment, {slug}.spirely.cloud
  # per church), this gem has exactly one deployment per install, so there's
  # no per-church slug subdomain to fall back to by default.
  def primary_hostname
    verified_primary_domain = custom_domains.find { |d| d.primary? && d.verified? }
    verified_primary_domain&.hostname || default_hostname
  end

  # Host for a church with no verified custom domain. One fixed host for a
  # self-hosted install; spirely-cloud overrides this per church.
  def default_hostname
    ENV.fetch("APP_HOST", "localhost:3000")
  end

  private

  # The request's custom domain, when it belongs to this church.
  def current_domain
    domain = Current.custom_domain
    domain if domain && domain.church_id == id
  end

  def logo_within_size_and_type_limits
    return unless logo.attached?

    errors.add(:logo, "must be smaller than #{MAX_LOGO_SIZE / 1.megabyte}MB") if logo.blob.byte_size > MAX_LOGO_SIZE
    errors.add(:logo, "must be a PNG, JPEG, SVG, or WebP image") unless ALLOWED_LOGO_TYPES.include?(logo.blob.content_type)
  end
end
