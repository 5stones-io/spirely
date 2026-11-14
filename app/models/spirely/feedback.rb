module Spirely
  # Feedback or a request someone at a church sent its staff (5ST-80):
  # something they noticed, supplies a room needs, how an event went, or
  # anything else, with pictures and documents attached. Only admins and
  # owners see it; the sender sees their own and its status.
  class Feedback < ApplicationRecord
    CATEGORIES = %w[noticed supplies reflection general].freeze
    CATEGORY_LABELS = {
      "noticed" => "Something I noticed", "supplies" => "Supplies needed",
      "reflection" => "Event reflection", "general" => "General feedback",
    }.freeze
    # How an event went; only event reflections have one.
    TONES = %w[went_well mixed didnt_go_well].freeze
    TONE_LABELS = { "went_well" => "Went well", "mixed" => "Mixed", "didnt_go_well" => "Didn't go well" }.freeze
    STATUSES = %w[new in_progress done].freeze
    SENDER_ROLES = %w[staff parent member].freeze

    MAX_ATTACHMENTS = 5
    MAX_ATTACHMENT_SIZE = 10.megabytes
    PICTURE_TYPES = Spirely::FamilyPost::PHOTO_TYPES
    # Office files are zip files inside, so these are told apart by name
    # once the contents show a zip (see #detect_type).
    DOCUMENT_TYPES = %w[
      application/pdf
      application/vnd.openxmlformats-officedocument.presentationml.presentation
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    ].freeze
    OFFICE_TYPES = DOCUMENT_TYPES - %w[application/pdf]

    # An attachment that breaks the rules above; the message is shown to
    # the sender as is.
    class AttachmentError < StandardError; end

    belongs_to :church
    belongs_to :account, class_name: "::Account", optional: true
    belongs_to :family, class_name: "Spirely::Family", optional: true
    belongs_to :task, class_name: "Spirely::Task", optional: true

    # Purged with the feedback (Active Storage's default).
    has_many_attached :attachments

    validates :category, inclusion: { in: CATEGORIES }
    validates :tone, inclusion: { in: TONES }, allow_nil: true
    validates :status, inclusion: { in: STATUSES }
    validates :sender_role, inclusion: { in: SENDER_ROLES }
    validates :body, presence: true, length: { maximum: 5000 }
    validates :about, length: { maximum: 200 }
    validates :staff_note, length: { maximum: 5000 }

    before_validation :default_status, on: :create
    before_validation :tone_only_for_reflections

    def category_label = CATEGORY_LABELS[category]
    def tone_label = tone && TONE_LABELS[tone]
    def sender_name = account&.name || account&.email || "Former member"

    def self.picture?(content_type) = PICTURE_TYPES.include?(content_type)

    # Checks every file before uploading any, so one bad file saves none.
    def attach_files(files)
      files = Array(files)
      raise AttachmentError, "You can attach up to #{MAX_ATTACHMENTS} files." if attachments.count + files.size > MAX_ATTACHMENTS

      types = files.map do |file|
        raise AttachmentError, "Each file has to be under 10 MB." if file.size > MAX_ATTACHMENT_SIZE
        detect_type(file).tap do |type|
          unless PICTURE_TYPES.include?(type) || DOCUMENT_TYPES.include?(type)
            raise AttachmentError, "Attachments have to be pictures, PDF, Word, PowerPoint or Excel files."
          end
        end
      end

      files.zip(types).each do |file, type|
        file.rewind
        blob = ActiveStorage::Blob.create_and_upload!(
          io: file, filename: file.original_filename, content_type: type,
          key: "church-#{church_id}/feedback/#{ActiveStorage::Blob.generate_unique_secure_token}",
        )
        attachments.attach(blob)
      end
    end

    # Oldest first: the order they were added.
    def ordered_attachments = attachments_attachments.sort_by(&:id)

    private

    # From the file's own bytes. Given a name, Marcel believes the
    # extension over the contents (a text file called .pdf comes back as a
    # PDF), so the name is only used to tell Office files apart once the
    # contents have shown a zip.
    def detect_type(file)
      file.rewind
      type = Marcel::MimeType.for(file.to_io)
      if type == "application/zip" || OFFICE_TYPES.include?(type)
        file.rewind
        named = Marcel::MimeType.for(file.to_io, name: file.original_filename.to_s)
        type = OFFICE_TYPES.include?(named) ? named : type
      end
      type
    end

    def default_status
      self.status ||= STATUSES.first
    end

    def tone_only_for_reflections
      self.tone = nil unless category == "reflection"
      self.tone = nil if tone.blank?
    end
  end
end
