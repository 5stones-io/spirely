module Spirely
  class FamilyPost < ApplicationRecord
    POST_TYPES = %w[prayer_request praise_report milestone accomplishment other].freeze
    AUDIENCES  = %w[church staff_only].freeze
    STATUSES   = %w[pending approved rejected].freeze
    MAX_PHOTOS = 10
    MAX_PHOTO_SIZE = 5.megabytes
    # Read from the file's own bytes, not the type the upload claims.
    PHOTO_TYPES = %w[image/jpeg image/png image/gif image/webp image/heic image/heif].freeze

    # A photo upload that breaks the rules above; the message is shown to
    # the family as is.
    class PhotoError < StandardError; end

    belongs_to :church
    belongs_to :family,      class_name: "Spirely::Family"
    belongs_to :guardian,    class_name: "Spirely::Guardian", optional: true
    belongs_to :child,       class_name: "Spirely::Child", optional: true
    belongs_to :moderated_by, class_name: "::Membership", foreign_key: :moderated_by_membership_id, optional: true

    # Purged with the post (Active Storage's default).
    has_many_attached :photos

    validates :body, presence: true
    validates :post_type, inclusion: { in: POST_TYPES }
    validates :audience, inclusion: { in: AUDIENCES }
    validates :status, inclusion: { in: STATUSES }
    validate :child_belongs_to_family

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

    def pending?  = status == "pending"
    def approved? = status == "approved"
    def rejected? = status == "rejected"

    def approve!(membership)
      update!(status: "approved", moderated_by: membership, moderated_at: Time.current, rejected_reason: nil)
    end

    def reject!(membership, reason: nil)
      update!(status: "rejected", moderated_by: membership, moderated_at: Time.current, rejected_reason: reason)
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
    def child_belongs_to_family
      return unless child && family
      errors.add(:child, "must belong to the posting family") unless child.family_id == family.id
    end
  end
end
