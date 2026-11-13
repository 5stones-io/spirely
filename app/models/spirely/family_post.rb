module Spirely
  class FamilyPost < ApplicationRecord
    POST_TYPES = %w[prayer_request praise_report milestone accomplishment other].freeze
    # "tagged": a staff post only the tagged children's families see (5ST-78).
    AUDIENCES  = %w[church staff_only tagged].freeze
    STATUSES   = %w[pending approved rejected].freeze
    MAX_PHOTOS = 10
    MAX_PHOTO_SIZE = 5.megabytes
    # Read from the file's own bytes, not the type the upload claims.
    PHOTO_TYPES = %w[image/jpeg image/png image/gif image/webp image/heic image/heif].freeze

    # A photo upload that breaks the rules above; the message is shown to
    # the family as is.
    class PhotoError < StandardError; end

    # Praying for, or answering, a post that can't take it (5ST-79). The
    # message is shown as is.
    class PrayerError < StandardError; end

    # A staff post's tags that break the rules (5ST-78). Shown as is.
    class TagError < StandardError; end

    belongs_to :church
    # A staff post (5ST-78) has no posting family, only its author.
    belongs_to :family,      class_name: "Spirely::Family", optional: true
    belongs_to :author,      class_name: "::Membership", foreign_key: :author_membership_id, optional: true
    belongs_to :guardian,    class_name: "Spirely::Guardian", optional: true
    belongs_to :child,       class_name: "Spirely::Child", optional: true
    belongs_to :moderated_by, class_name: "::Membership", foreign_key: :moderated_by_membership_id, optional: true

    # People praying for a prayer request (5ST-79).
    has_many :prayers, class_name: "Spirely::FamilyPostPrayer", dependent: :delete_all
    # A praise report can answer one of its family's prayer requests.
    belongs_to :answers_post, class_name: "Spirely::FamilyPost", optional: true
    has_one :answer_praise, class_name: "Spirely::FamilyPost", foreign_key: :answers_post_id,
                            inverse_of: :answers_post, dependent: :nullify

    # Children a staff post tags (5ST-78).
    has_many :post_children, class_name: "Spirely::FamilyPostChild", dependent: :delete_all
    has_many :tagged_children, through: :post_children, source: :child

    # Purged with the post (Active Storage's default).
    has_many_attached :photos

    validates :body, presence: true
    validates :family, presence: true, unless: :author_membership_id?
    validates :post_type, inclusion: { in: POST_TYPES }
    validates :audience, inclusion: { in: AUDIENCES }
    validates :status, inclusion: { in: STATUSES }
    validate :child_belongs_to_family
    validate :answers_own_prayer_request

    before_validation :default_post_type, on: :create
    before_validation :default_audience, on: :create
    before_validation :default_status, on: :create

    # The church-wide feed: only approved posts whose author chose the
    # "church" audience. A post's own family (any status, either
    # audience) is a separate concern, handled by controllers — this
    # scope is deliberately the narrower "would a stranger family see
    # this" definition, not "is this record moderated-clean."
    scope :visible_church_wide, -> { where(status: "approved", audience: "church") }
    scope :pending_moderation,  -> { where(status: "pending") }

    # What a family's feed holds: the church-wide feed, the family's own
    # posts, and staff posts that tag any of its children (5ST-78).
    scope :visible_to_family, ->(family) {
      where(<<~SQL.squish, approved: "approved", family_id: family.id)
        (status = :approved AND audience = 'church')
        OR family_id = :family_id
        OR (status = :approved AND audience = 'tagged' AND id IN (
          SELECT tags.family_post_id FROM spirely_family_post_children tags
          JOIN spirely_children kids ON kids.id = tags.child_id
          WHERE kids.family_id = :family_id))
      SQL
    }

    def staff_post? = author_membership_id.present?

    # Who wrote it: a staff post's author, or the posting guardian or family.
    def self.author_name(post)
      if post.staff_post? || post.family.nil?
        post.author&.account&.then { |a| a.name || a.email } || "Church staff"
      elsif post.guardian
        "#{post.guardian.first_name} #{post.guardian.last_name}".strip
      else
        post.family.primary_contact_name
      end
    end

    # A staff post to the families of the children it tags (5ST-78).
    # Approved straight away (only staff post these). A post with photos
    # can't tag a child whose family asked for no photos. Nothing is saved
    # unless it all checks out.
    def self.post_to_families!(church:, author:, body:, child_ids:, photos: nil)
      ids = Array(child_ids).map(&:to_i).uniq
      raise TagError, "Tag at least one child." if ids.empty?

      children = church.children.where(id: ids).to_a
      raise TagError, "Some of those children aren't at this church." if children.size != ids.size

      if photos.present? && (no_photos = children.find(&:no_photos?))
        raise TagError, "#{no_photos.first_name}'s family asked for no photos. Remove the photos or untag #{no_photos.first_name} to post."
      end

      transaction do
        post = create!(church: church, author: author, body: body, post_type: "other", audience: "tagged", status: "approved")
        children.each { |child| post.post_children.create!(church: church, child: child) }
        post.attach_photos(photos) if photos.present?
        post
      end
    end

    # Takes this family's children off a staff post, so it leaves the
    # family's feed (5ST-78). Other families' tags stay.
    def remove_tags!(family)
      post_children.where(child_id: family.children.select(:id)).delete_all
    end

    def pending?  = status == "pending"
    def approved? = status == "approved"
    def rejected? = status == "rejected"

    # Its family can change it until staff have reviewed it: while pending,
    # or auto-approved and never moderated.
    def editable? = pending? || moderated_at.nil?

    def approve!(membership)
      update!(status: "approved", moderated_by: membership, moderated_at: Time.current, rejected_reason: nil)
    end

    def reject!(membership, reason: nil)
      update!(status: "rejected", moderated_by: membership, moderated_at: Time.current, rejected_reason: reason)
    end

    def prayer_request? = post_type == "prayer_request"
    def answered? = answered_at.present?

    def praying?(account) = prayers.exists?(account_id: account.id)

    # Saying you're praying twice still counts once.
    def pray!(account)
      raise PrayerError, "You can only pray for prayer requests." unless prayer_request?
      prayers.find_or_create_by!(account: account) { |p| p.church_id = church_id }
    rescue ActiveRecord::RecordNotUnique
      prayers.find_by!(account: account)
    end

    def stop_praying!(account)
      prayers.where(account_id: account.id).first&.destroy!
    end

    # Marks this prayer request answered. With share_as_praise, the note
    # also goes out as a praise report from the same family, about the
    # same child, to the same audience, reviewed like any new post.
    # Returns that praise report, or nil.
    def mark_answered!(note:, share_as_praise: false, guardian: nil, photos: nil)
      raise PrayerError, "Only prayer requests can be marked answered." unless prayer_request?
      raise PrayerError, "This request is already marked answered." if answered?

      transaction do
        update!(answered_at: Time.current, answer_note: note.presence)
        next nil unless share_as_praise

        praise = self.class.create!(
          church: church, family: family, guardian: guardian || self.guardian, child: child,
          post_type: "praise_report", audience: audience, body: note.to_s.strip, answers_post: self,
        )
        praise.attach_photos(photos) if photos.present?
        praise
      end
    end

    # Checks every file before uploading any, so a bad one leaves nothing
    # behind. Keys are prefixed per church, like incident photos.
    def attach_photos(files)
      files = Array(files)
      raise PhotoError, "A post can have up to #{MAX_PHOTOS} photos." if photos.count + files.size > MAX_PHOTOS
      types = files.map do |file|
        raise PhotoError, "Each photo has to be under 5 MB." if file.size > MAX_PHOTO_SIZE
        file.rewind
        Marcel::MimeType.for(file.to_io).tap do |type|
          raise PhotoError, "Photos have to be pictures (JPG, PNG, GIF, WebP or HEIC)." unless PHOTO_TYPES.include?(type)
        end
      end

      files.zip(types).each do |file, type|
        file.rewind
        blob = ActiveStorage::Blob.create_and_upload!(
          io: file, filename: file.original_filename, content_type: type,
          key: "church-#{church_id}/posts/#{ActiveStorage::Blob.generate_unique_secure_token}",
        )
        photos.attach(blob)
      end
    end

    # Oldest first: the order they were added.
    def ordered_photos = photos_attachments.sort_by(&:id)

    private

    def default_post_type
      self.post_type ||= POST_TYPES.first
    end

    def default_audience
      self.audience ||= AUDIENCES.first
    end

    # Skips the moderation queue entirely unless the posting church has
    # explicitly turned it on (Church#family_posts_moderation_enabled) —
    # most churches get an auto-published feed by default, same "off
    # unless asked for" instinct as every other per-church toggle here.
    def default_status
      self.status ||= church&.family_posts_moderation_enabled? ? "pending" : "approved"
    end

    # child_id is optional, but when present it has to actually be this
    # family's own kid — nothing else stops a crafted request from
    # attributing a post to an unrelated family's child otherwise, since
    # Child isn't scoped through Family at the DB/FK level.
    def answers_own_prayer_request
      return unless answers_post
      return if answers_post.prayer_request? && answers_post.family_id == family_id && post_type == "praise_report"
      errors.add(:answers_post, "must be one of this family's prayer requests")
    end

    def child_belongs_to_family
      return unless child && family
      errors.add(:child, "must belong to the posting family") unless child.family_id == family.id
    end
  end
end
