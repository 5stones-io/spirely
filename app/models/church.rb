class Church < ApplicationRecord
  KNOWN_MODULES = %w[kidsmin].freeze
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

  def module_enabled?(name)
    enabled_modules.include?(name.to_s)
  end

  # What the app shell's brand mark actually shows — falls back to the
  # church's real `name` when no shorter display_name has been set.
  def brand_name
    display_name.presence || name
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
    verified_primary_domain&.hostname || ENV.fetch("APP_HOST", "localhost:3000")
  end

  private

  def logo_within_size_and_type_limits
    return unless logo.attached?

    errors.add(:logo, "must be smaller than #{MAX_LOGO_SIZE / 1.megabyte}MB") if logo.blob.byte_size > MAX_LOGO_SIZE
    errors.add(:logo, "must be a PNG, JPEG, SVG, or WebP image") unless ALLOWED_LOGO_TYPES.include?(logo.blob.content_type)
  end
end
